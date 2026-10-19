// GPU host harness for the Metal ed25519 vanity-key grinder.
//
// This process searches for a candidate seed on the GPU. Before ever
// writing a key file, it independently re-derives the keypair from the
// candidate seed using Apple's own CryptoKit (a trusted implementation
// entirely separate from this Metal/MSL code) and re-checks the suffix
// match on that independently-derived public key. Only if CryptoKit agrees
// does it write id_ed25519/id_ed25519.pub. If it ever disagrees, that
// indicates a bug in the GPU implementation, and this program stops rather
// than silently continuing -- a GPU bug can waste compute time searching,
// but it can never result in a wrong key being written.

import Foundation
import Metal
import Security
import CryptoKit

struct Args {
    var suffixes: [String] = []
    var batchSize: Int = 2_000_000
    var metalSource: String = "fe25519.metal"
    var tablePath: String = "base_table.bin"
    var outDir: String = "."
    var comment: String = "vanity-key"
}

func parseArgs() -> Args {
    var a = Args()
    for arg in CommandLine.arguments.dropFirst() {
        guard let eq = arg.firstIndex(of: "=") else { continue }
        let key = String(arg[arg.startIndex..<eq])
        let value = String(arg[arg.index(after: eq)...])
        switch key {
        case "--suffixes": a.suffixes = value.split(separator: ",").map(String.init)
        case "--batch-size": a.batchSize = Int(value) ?? a.batchSize
        case "--metal-src": a.metalSource = value
        case "--table": a.tablePath = value
        case "--out": a.outDir = value
        case "--comment": a.comment = value
        default: fputs("unknown flag: \(key)\n", stderr)
        }
    }
    return a
}

setbuf(stdout, nil)
let args = parseArgs()
let maxTargetLen = 32  // must match MAX_TARGET_LEN in fe25519.metal
let maxTargets = 8     // must match MAX_TARGETS in fe25519.metal
let base64Chars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

guard !args.suffixes.isEmpty else {
    fputs("""
    usage: grind --suffixes=<comma-separated targets> [--batch-size=N] [--out=DIR] [--comment=TEXT]

    Each target is matched against the end of your public key's base64 and
    can be any length from 1 to \(maxTargetLen) characters (base64 only:
    A-Z a-z 0-9 + /) -- targets don't need to share a length. Up to
    \(maxTargets) targets per run. Example: --suffixes=/alice12,+Alice12,ab

    \n
    """, stderr)
    exit(1)
}
guard args.suffixes.count <= maxTargets else {
    fatalError("\(args.suffixes.count) targets given, but at most \(maxTargets) are supported per run")
}
for s in args.suffixes {
    guard (1...maxTargetLen).contains(s.utf8.count) else {
        fatalError("target '\(s)' is \(s.utf8.count) bytes; targets must be 1-\(maxTargetLen) characters")
    }
    guard s.allSatisfy({ base64Chars.contains($0) }) else {
        fatalError("target '\(s)' contains a character that can never appear in base64 (only A-Z a-z 0-9 + / are valid) -- it could never match")
    }
}

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("no Metal device found")
}

let source: String
do {
    source = try String(contentsOfFile: args.metalSource, encoding: .utf8)
} catch {
    fatalError("could not read \(args.metalSource): \(error)")
}

let library: MTLLibrary
do {
    library = try device.makeLibrary(source: source, options: nil)
} catch {
    fatalError("Metal compile error: \(error)")
}

guard let grindFunction = library.makeFunction(name: "k_grind") else {
    fatalError("k_grind not found in compiled library")
}
let pipeline: MTLComputePipelineState
do {
    pipeline = try device.makeComputePipelineState(function: grindFunction)
} catch {
    fatalError("pipeline error: \(error)")
}

guard let queue = device.makeCommandQueue() else {
    fatalError("could not create command queue")
}

func randomBytes(_ count: Int) -> Data {
    var data = Data(count: count)
    let result = data.withUnsafeMutableBytes { ptr -> Int32 in
        SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
    }
    guard result == errSecSuccess else { fatalError("SecRandomCopyBytes failed: \(result)") }
    return data
}

func expectedTries(_ suffixes: [String], alphabetSize: Double = 64) -> Double {
    let perTarget = suffixes.map { pow(alphabetSize, -Double($0.utf8.count)) }
    return 1.0 / perTarget.reduce(0, +)
}

// ---- OpenSSH private-key construction (same wire format validated earlier
// against a real `ssh-keygen -y` round-trip), using CryptoKit's own
// Ed25519 implementation as the independent source of truth. ----

func beBytes(_ v: UInt32) -> [UInt8] {
    withUnsafeBytes(of: v.bigEndian) { Array($0) }
}

func sshString(_ bytes: [UInt8]) -> [UInt8] {
    beBytes(UInt32(bytes.count)) + bytes
}

func sshPubkeyBlob(pubkey: Data) -> [UInt8] {
    sshString(Array("ssh-ed25519".utf8)) + sshString(Array(pubkey))
}

func buildOpenSSHPrivateKeyPEM(seed: Data, pubkey: Data, comment: String) -> String {
    var checkintBytes = [UInt8](repeating: 0, count: 4)
    _ = SecRandomCopyBytes(kSecRandomDefault, 4, &checkintBytes)

    var privSection: [UInt8] = []
    privSection += checkintBytes
    privSection += checkintBytes
    privSection += sshString(Array("ssh-ed25519".utf8))
    privSection += sshString(Array(pubkey))
    privSection += sshString(Array(seed) + Array(pubkey)) // priv = seed(32) + pubkey(32)
    privSection += sshString(Array(comment.utf8))
    var pad: UInt8 = 1
    while privSection.count % 8 != 0 {
        privSection.append(pad)
        pad += 1
    }

    var body: [UInt8] = []
    body += Array("openssh-key-v1\0".utf8)
    body += sshString(Array("none".utf8)) // ciphername
    body += sshString(Array("none".utf8)) // kdfname
    body += sshString([])                 // kdfoptions
    body += beBytes(1)                    // number of keys
    body += sshString(sshPubkeyBlob(pubkey: pubkey))
    body += sshString(privSection)

    let b64 = Data(body).base64EncodedString()
    var lines: [String] = []
    var idx = b64.startIndex
    while idx < b64.endIndex {
        let end = b64.index(idx, offsetBy: 64, limitedBy: b64.endIndex) ?? b64.endIndex
        lines.append(String(b64[idx..<end]))
        idx = end
    }
    return "-----BEGIN OPENSSH PRIVATE KEY-----\n" + lines.joined(separator: "\n") + "\n-----END OPENSSH PRIVATE KEY-----\n"
}

// Independently re-derives the keypair from a GPU-reported candidate seed
// using CryptoKit (not this program's own Metal/MSL crypto code), re-checks
// the suffix match, and only then writes the key files. Returns true if a
// key was written.
func verifyAndWrite(seed: Data, args: Args) -> Bool {
    guard let privKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
        fputs("invalid seed for CryptoKit\n", stderr)
        return false
    }
    let pubkey = privKey.publicKey.rawRepresentation
    let b64 = Data(sshPubkeyBlob(pubkey: pubkey)).base64EncodedString()

    guard args.suffixes.contains(where: { b64.hasSuffix($0) }) else {
        fputs("REJECTED: independent CryptoKit re-derivation does not match targets \(args.suffixes) (got ...\(b64.suffix(12))) -- refusing to write, this indicates a bug in the GPU implementation\n", stderr)
        return false
    }

    let pem = buildOpenSSHPrivateKeyPEM(seed: seed, pubkey: pubkey, comment: args.comment)
    let pubLine = "ssh-ed25519 \(b64) \(args.comment)\n"
    let privPath = (args.outDir as NSString).appendingPathComponent("id_ed25519")
    let pubPath = (args.outDir as NSString).appendingPathComponent("id_ed25519.pub")

    do {
        try pem.write(toFile: privPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privPath)
        try pubLine.write(toFile: pubPath, atomically: true, encoding: .utf8)
    } catch {
        fputs("write error: \(error)\n", stderr)
        return false
    }

    print("verified independently via CryptoKit; wrote \(privPath) and \(pubPath)")
    print("ssh-ed25519 \(b64) \(args.comment)")
    return true
}

// Each target gets its own fixed-size maxTargetLen slot (zero-padded; the
// kernel only reads the first target_lens[t] bytes of it), so targets can
// mix lengths freely in one run.
let targetsBuf = args.suffixes.reduce(into: Data()) { acc, suffix in
    var slot = Array(suffix.utf8)
    slot += [UInt8](repeating: 0, count: maxTargetLen - slot.count)
    acc.append(contentsOf: slot)
}
let targetLensBuf = args.suffixes.reduce(into: Data()) { acc, suffix in
    // Native byte order here (not beBytes/big-endian): the kernel reads this
    // as a plain `uint` buffer, not an SSH-wire-format length prefix.
    var len = UInt32(suffix.utf8.count)
    acc.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
}
let maxMatches: UInt32 = 64

guard let tableData = FileManager.default.contents(atPath: args.tablePath) else {
    fatalError("could not read \(args.tablePath)")
}
guard tableData.count == 256 * 64 else {
    fatalError("\(args.tablePath) is \(tableData.count) bytes, expected \(256 * 64)")
}
// Loaded once and reused for every dispatch: it's the same fixed table of
// precomputed base-point multiples for the whole run, not per-batch data.
guard let tableBuf = device.makeBuffer(bytes: (tableData as NSData).bytes, length: tableData.count, options: .storageModeShared) else {
    fatalError("could not create table buffer")
}

print("targets: \(args.suffixes)")
let avgTries = expectedTries(args.suffixes)
print("expected tries (average, assuming uniform random keys): \(avgTries)")
print("batch size: \(args.batchSize)")

var totalTries: UInt64 = 0
let startTime = Date()
var lastReport = Date()

// Runs one GPU batch and returns plain Swift values only (no Metal/ObjC
// objects escape this function). Must be called inside an autoreleasepool:
// Metal buffers/command buffers/encoders are Objective-C objects, and a
// command-line tool has no run loop to drain the autorelease pool on its
// own, so without this every iteration's Metal objects pile up and the
// process's memory grows unboundedly.
func runBatch(batchSize: Int, tableBuf: MTLBuffer, targetsBuf: Data, targetLensBuf: Data, numTargets: UInt32, maxMatches: UInt32) -> (count: UInt32, matchedSeeds: [Data]) {
    let seeds = randomBytes(batchSize * 32)
    var numTargetsVar = numTargets
    var maxMatchesVar = maxMatches

    guard
        let seedsBuf = device.makeBuffer(bytes: (seeds as NSData).bytes, length: seeds.count, options: .storageModeShared),
        let targetsBufMTL = device.makeBuffer(bytes: (targetsBuf as NSData).bytes, length: max(targetsBuf.count, 1), options: .storageModeShared),
        let targetLensBufMTL = device.makeBuffer(bytes: (targetLensBuf as NSData).bytes, length: max(targetLensBuf.count, 1), options: .storageModeShared),
        let countBuf = device.makeBuffer(length: 4, options: .storageModeShared),
        let matchesBuf = device.makeBuffer(length: Int(maxMatches) * 32, options: .storageModeShared),
        let numTargetsBuf = device.makeBuffer(bytes: &numTargetsVar, length: 4, options: .storageModeShared),
        let maxMatchesBuf = device.makeBuffer(bytes: &maxMatchesVar, length: 4, options: .storageModeShared)
    else {
        fatalError("buffer allocation failed")
    }
    memset(countBuf.contents(), 0, 4)

    guard
        let cmd = queue.makeCommandBuffer(),
        let enc = cmd.makeComputeCommandEncoder()
    else {
        fatalError("command encoder creation failed")
    }
    enc.setComputePipelineState(pipeline)
    enc.setBuffer(seedsBuf, offset: 0, index: 0)
    enc.setBuffer(tableBuf, offset: 0, index: 1)
    enc.setBuffer(targetsBufMTL, offset: 0, index: 2)
    enc.setBuffer(targetLensBufMTL, offset: 0, index: 3)
    enc.setBuffer(numTargetsBuf, offset: 0, index: 4)
    enc.setBuffer(countBuf, offset: 0, index: 5)
    enc.setBuffer(matchesBuf, offset: 0, index: 6)
    enc.setBuffer(maxMatchesBuf, offset: 0, index: 7)

    let tgSize = min(batchSize, pipeline.maxTotalThreadsPerThreadgroup)
    enc.dispatchThreads(MTLSize(width: batchSize, height: 1, depth: 1),
                         threadsPerThreadgroup: MTLSize(width: tgSize, height: 1, depth: 1))
    enc.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()

    let count = countBuf.contents().load(as: UInt32.self)
    var matchedSeeds: [Data] = []
    if count > 0 {
        let n = min(Int(count), Int(maxMatches))
        let matchPtr = matchesBuf.contents().bindMemory(to: UInt8.self, capacity: n * 32)
        for i in 0..<n {
            matchedSeeds.append(Data(bytes: matchPtr.advanced(by: i * 32), count: 32))
        }
    }
    return (count, matchedSeeds)
}

searchLoop: while true {
    let (count, matchedSeeds) = autoreleasepool {
        runBatch(batchSize: args.batchSize, tableBuf: tableBuf, targetsBuf: targetsBuf, targetLensBuf: targetLensBuf, numTargets: UInt32(args.suffixes.count), maxMatches: maxMatches)
    }

    totalTries += UInt64(args.batchSize)

    if count > 0 {
        print("\n*** \(count) candidate match(es) found, verifying independently via CryptoKit... ***")
        for seed in matchedSeeds {
            if verifyAndWrite(seed: seed, args: args) {
                print("SUCCESS after \(totalTries) tries, elapsed \(Date().timeIntervalSince(startTime))s")
                break searchLoop
            } else {
                fputs("WARNING: independent verification rejected a GPU-reported match -- this indicates a bug in the GPU implementation, investigate before trusting this grinder further\n", stderr)
            }
        }
    }

    let now = Date()
    if now.timeIntervalSince(lastReport) >= 30 {
        let elapsed = now.timeIntervalSince(startTime)
        let rate = Double(totalTries) / elapsed
        let eta = avgTries / rate
        print("[\(Int(elapsed))s] \(totalTries) tries, \(Int(rate))/s, ETA ~\(Int(eta / 3600))h")
        lastReport = now
    }
}
