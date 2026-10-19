#include <metal_stdlib>
#include <metal_atomic>
using namespace metal;

// Field arithmetic for GF(2^255 - 19), ported from libsodium's ref10 fe_25_5
// representation (10 int32 limbs, alternating radix 2^26/2^25), plus an
// inversion addition chain ported from filippo.io/edwards25519 (which uses
// the same classical 255-squarings/11-multiplications sequence, expressed
// there over a 5x51-bit representation -- the sequence of squarings and
// multiplications is representation-independent, so it's applied here
// directly to the 10-limb ops below).

inline long ld3(thread const uchar* in) {
    long r = (long)in[0];
    r |= ((long)in[1]) << 8;
    r |= ((long)in[2]) << 16;
    return r;
}

inline long ld4(thread const uchar* in) {
    long r = (long)in[0];
    r |= ((long)in[1]) << 8;
    r |= ((long)in[2]) << 16;
    r |= ((long)in[3]) << 24;
    return r;
}

inline void fe_frombytes(thread int* h, thread const uchar* s) {
    long h0 = ld4(s);
    long h1 = ld3(s + 4) << 6;
    long h2 = ld3(s + 7) << 5;
    long h3 = ld3(s + 10) << 3;
    long h4 = ld3(s + 13) << 2;
    long h5 = ld4(s + 16);
    long h6 = ld3(s + 20) << 7;
    long h7 = ld3(s + 23) << 5;
    long h8 = ld3(s + 26) << 4;
    long h9 = (ld3(s + 29) & 8388607) << 2;

    long carry0, carry1, carry2, carry3, carry4, carry5, carry6, carry7, carry8, carry9;

    carry9 = (h9 + ((long)1 << 24)) >> 25;
    h0 += carry9 * 19;
    h9 -= carry9 * ((long)1 << 25);
    carry1 = (h1 + ((long)1 << 24)) >> 25;
    h2 += carry1;
    h1 -= carry1 * ((long)1 << 25);
    carry3 = (h3 + ((long)1 << 24)) >> 25;
    h4 += carry3;
    h3 -= carry3 * ((long)1 << 25);
    carry5 = (h5 + ((long)1 << 24)) >> 25;
    h6 += carry5;
    h5 -= carry5 * ((long)1 << 25);
    carry7 = (h7 + ((long)1 << 24)) >> 25;
    h8 += carry7;
    h7 -= carry7 * ((long)1 << 25);

    carry0 = (h0 + ((long)1 << 25)) >> 26;
    h1 += carry0;
    h0 -= carry0 * ((long)1 << 26);
    carry2 = (h2 + ((long)1 << 25)) >> 26;
    h3 += carry2;
    h2 -= carry2 * ((long)1 << 26);
    carry4 = (h4 + ((long)1 << 25)) >> 26;
    h5 += carry4;
    h4 -= carry4 * ((long)1 << 26);
    carry6 = (h6 + ((long)1 << 25)) >> 26;
    h7 += carry6;
    h6 -= carry6 * ((long)1 << 26);
    carry8 = (h8 + ((long)1 << 25)) >> 26;
    h9 += carry8;
    h8 -= carry8 * ((long)1 << 26);

    h[0] = (int)h0; h[1] = (int)h1; h[2] = (int)h2; h[3] = (int)h3; h[4] = (int)h4;
    h[5] = (int)h5; h[6] = (int)h6; h[7] = (int)h7; h[8] = (int)h8; h[9] = (int)h9;
}

inline void fe_reduce(thread int* h, thread const int* f) {
    int h0 = f[0], h1 = f[1], h2 = f[2], h3 = f[3], h4 = f[4];
    int h5 = f[5], h6 = f[6], h7 = f[7], h8 = f[8], h9 = f[9];

    int q;
    q = (19 * h9 + ((int)1 << 24)) >> 25;
    q = (h0 + q) >> 26;
    q = (h1 + q) >> 25;
    q = (h2 + q) >> 26;
    q = (h3 + q) >> 25;
    q = (h4 + q) >> 26;
    q = (h5 + q) >> 25;
    q = (h6 + q) >> 26;
    q = (h7 + q) >> 25;
    q = (h8 + q) >> 26;
    q = (h9 + q) >> 25;

    h0 += 19 * q;

    int carry0, carry1, carry2, carry3, carry4, carry5, carry6, carry7, carry8, carry9;
    carry0 = h0 >> 26; h1 += carry0; h0 -= carry0 * ((int)1 << 26);
    carry1 = h1 >> 25; h2 += carry1; h1 -= carry1 * ((int)1 << 25);
    carry2 = h2 >> 26; h3 += carry2; h2 -= carry2 * ((int)1 << 26);
    carry3 = h3 >> 25; h4 += carry3; h3 -= carry3 * ((int)1 << 25);
    carry4 = h4 >> 26; h5 += carry4; h4 -= carry4 * ((int)1 << 26);
    carry5 = h5 >> 25; h6 += carry5; h5 -= carry5 * ((int)1 << 25);
    carry6 = h6 >> 26; h7 += carry6; h6 -= carry6 * ((int)1 << 26);
    carry7 = h7 >> 25; h8 += carry7; h7 -= carry7 * ((int)1 << 25);
    carry8 = h8 >> 26; h9 += carry8; h8 -= carry8 * ((int)1 << 26);
    carry9 = h9 >> 25; h9 -= carry9 * ((int)1 << 25);

    h[0]=h0; h[1]=h1; h[2]=h2; h[3]=h3; h[4]=h4; h[5]=h5; h[6]=h6; h[7]=h7; h[8]=h8; h[9]=h9;
}

inline void fe_tobytes(thread uchar* s, thread const int* h) {
    int t[10];
    fe_reduce(t, h);
    s[0]  = (uchar)(t[0] >> 0);
    s[1]  = (uchar)(t[0] >> 8);
    s[2]  = (uchar)(t[0] >> 16);
    s[3]  = (uchar)((t[0] >> 24) | (t[1] * ((int)1 << 2)));
    s[4]  = (uchar)(t[1] >> 6);
    s[5]  = (uchar)(t[1] >> 14);
    s[6]  = (uchar)((t[1] >> 22) | (t[2] * ((int)1 << 3)));
    s[7]  = (uchar)(t[2] >> 5);
    s[8]  = (uchar)(t[2] >> 13);
    s[9]  = (uchar)((t[2] >> 21) | (t[3] * ((int)1 << 5)));
    s[10] = (uchar)(t[3] >> 3);
    s[11] = (uchar)(t[3] >> 11);
    s[12] = (uchar)((t[3] >> 19) | (t[4] * ((int)1 << 6)));
    s[13] = (uchar)(t[4] >> 2);
    s[14] = (uchar)(t[4] >> 10);
    s[15] = (uchar)(t[4] >> 18);
    s[16] = (uchar)(t[5] >> 0);
    s[17] = (uchar)(t[5] >> 8);
    s[18] = (uchar)(t[5] >> 16);
    s[19] = (uchar)((t[5] >> 24) | (t[6] * ((int)1 << 1)));
    s[20] = (uchar)(t[6] >> 7);
    s[21] = (uchar)(t[6] >> 15);
    s[22] = (uchar)((t[6] >> 23) | (t[7] * ((int)1 << 3)));
    s[23] = (uchar)(t[7] >> 5);
    s[24] = (uchar)(t[7] >> 13);
    s[25] = (uchar)((t[7] >> 21) | (t[8] * ((int)1 << 4)));
    s[26] = (uchar)(t[8] >> 4);
    s[27] = (uchar)(t[8] >> 12);
    s[28] = (uchar)((t[8] >> 20) | (t[9] * ((int)1 << 6)));
    s[29] = (uchar)(t[9] >> 2);
    s[30] = (uchar)(t[9] >> 10);
    s[31] = (uchar)(t[9] >> 18);
}

inline void fe_add(thread int* h, thread const int* f, thread const int* g) {
    for (int i = 0; i < 10; i++) h[i] = f[i] + g[i];
}

inline void fe_sub(thread int* h, thread const int* f, thread const int* g) {
    for (int i = 0; i < 10; i++) h[i] = f[i] - g[i];
}

inline void fe_mul(thread int* h, thread const int* f, thread const int* g) {
    int f0=f[0],f1=f[1],f2=f[2],f3=f[3],f4=f[4],f5=f[5],f6=f[6],f7=f[7],f8=f[8],f9=f[9];
    int g0=g[0],g1=g[1],g2=g[2],g3=g[3],g4=g[4],g5=g[5],g6=g[6],g7=g[7],g8=g[8],g9=g[9];

    int g1_19 = 19*g1, g2_19 = 19*g2, g3_19 = 19*g3, g4_19 = 19*g4, g5_19 = 19*g5;
    int g6_19 = 19*g6, g7_19 = 19*g7, g8_19 = 19*g8, g9_19 = 19*g9;
    int f1_2 = 2*f1, f3_2 = 2*f3, f5_2 = 2*f5, f7_2 = 2*f7, f9_2 = 2*f9;

    long f0g0 = f0*(long)g0, f0g1 = f0*(long)g1, f0g2 = f0*(long)g2, f0g3 = f0*(long)g3,
         f0g4 = f0*(long)g4, f0g5 = f0*(long)g5, f0g6 = f0*(long)g6, f0g7 = f0*(long)g7,
         f0g8 = f0*(long)g8, f0g9 = f0*(long)g9;
    long f1g0 = f1*(long)g0, f1g1_2 = f1_2*(long)g1, f1g2 = f1*(long)g2, f1g3_2 = f1_2*(long)g3,
         f1g4 = f1*(long)g4, f1g5_2 = f1_2*(long)g5, f1g6 = f1*(long)g6, f1g7_2 = f1_2*(long)g7,
         f1g8 = f1*(long)g8, f1g9_38 = f1_2*(long)g9_19;
    long f2g0 = f2*(long)g0, f2g1 = f2*(long)g1, f2g2 = f2*(long)g2, f2g3 = f2*(long)g3,
         f2g4 = f2*(long)g4, f2g5 = f2*(long)g5, f2g6 = f2*(long)g6, f2g7 = f2*(long)g7,
         f2g8_19 = f2*(long)g8_19, f2g9_19 = f2*(long)g9_19;
    long f3g0 = f3*(long)g0, f3g1_2 = f3_2*(long)g1, f3g2 = f3*(long)g2, f3g3_2 = f3_2*(long)g3,
         f3g4 = f3*(long)g4, f3g5_2 = f3_2*(long)g5, f3g6 = f3*(long)g6, f3g7_38 = f3_2*(long)g7_19,
         f3g8_19 = f3*(long)g8_19, f3g9_38 = f3_2*(long)g9_19;
    long f4g0 = f4*(long)g0, f4g1 = f4*(long)g1, f4g2 = f4*(long)g2, f4g3 = f4*(long)g3,
         f4g4 = f4*(long)g4, f4g5 = f4*(long)g5, f4g6_19 = f4*(long)g6_19, f4g7_19 = f4*(long)g7_19,
         f4g8_19 = f4*(long)g8_19, f4g9_19 = f4*(long)g9_19;
    long f5g0 = f5*(long)g0, f5g1_2 = f5_2*(long)g1, f5g2 = f5*(long)g2, f5g3_2 = f5_2*(long)g3,
         f5g4 = f5*(long)g4, f5g5_38 = f5_2*(long)g5_19, f5g6_19 = f5*(long)g6_19, f5g7_38 = f5_2*(long)g7_19,
         f5g8_19 = f5*(long)g8_19, f5g9_38 = f5_2*(long)g9_19;
    long f6g0 = f6*(long)g0, f6g1 = f6*(long)g1, f6g2 = f6*(long)g2, f6g3 = f6*(long)g3,
         f6g4_19 = f6*(long)g4_19, f6g5_19 = f6*(long)g5_19, f6g6_19 = f6*(long)g6_19, f6g7_19 = f6*(long)g7_19,
         f6g8_19 = f6*(long)g8_19, f6g9_19 = f6*(long)g9_19;
    long f7g0 = f7*(long)g0, f7g1_2 = f7_2*(long)g1, f7g2 = f7*(long)g2, f7g3_38 = f7_2*(long)g3_19,
         f7g4_19 = f7*(long)g4_19, f7g5_38 = f7_2*(long)g5_19, f7g6_19 = f7*(long)g6_19, f7g7_38 = f7_2*(long)g7_19,
         f7g8_19 = f7*(long)g8_19, f7g9_38 = f7_2*(long)g9_19;
    long f8g0 = f8*(long)g0, f8g1 = f8*(long)g1, f8g2_19 = f8*(long)g2_19, f8g3_19 = f8*(long)g3_19,
         f8g4_19 = f8*(long)g4_19, f8g5_19 = f8*(long)g5_19, f8g6_19 = f8*(long)g6_19, f8g7_19 = f8*(long)g7_19,
         f8g8_19 = f8*(long)g8_19, f8g9_19 = f8*(long)g9_19;
    long f9g0 = f9*(long)g0, f9g1_38 = f9_2*(long)g1_19, f9g2_19 = f9*(long)g2_19, f9g3_38 = f9_2*(long)g3_19,
         f9g4_19 = f9*(long)g4_19, f9g5_38 = f9_2*(long)g5_19, f9g6_19 = f9*(long)g6_19, f9g7_38 = f9_2*(long)g7_19,
         f9g8_19 = f9*(long)g8_19, f9g9_38 = f9_2*(long)g9_19;

    long h0 = f0g0+f1g9_38+f2g8_19+f3g7_38+f4g6_19+f5g5_38+f6g4_19+f7g3_38+f8g2_19+f9g1_38;
    long h1 = f0g1+f1g0+f2g9_19+f3g8_19+f4g7_19+f5g6_19+f6g5_19+f7g4_19+f8g3_19+f9g2_19;
    long h2 = f0g2+f1g1_2+f2g0+f3g9_38+f4g8_19+f5g7_38+f6g6_19+f7g5_38+f8g4_19+f9g3_38;
    long h3 = f0g3+f1g2+f2g1+f3g0+f4g9_19+f5g8_19+f6g7_19+f7g6_19+f8g5_19+f9g4_19;
    long h4 = f0g4+f1g3_2+f2g2+f3g1_2+f4g0+f5g9_38+f6g8_19+f7g7_38+f8g6_19+f9g5_38;
    long h5 = f0g5+f1g4+f2g3+f3g2+f4g1+f5g0+f6g9_19+f7g8_19+f8g7_19+f9g6_19;
    long h6 = f0g6+f1g5_2+f2g4+f3g3_2+f4g2+f5g1_2+f6g0+f7g9_38+f8g8_19+f9g7_38;
    long h7 = f0g7+f1g6+f2g5+f3g4+f4g3+f5g2+f6g1+f7g0+f8g9_19+f9g8_19;
    long h8 = f0g8+f1g7_2+f2g6+f3g5_2+f4g4+f5g3_2+f6g2+f7g1_2+f8g0+f9g9_38;
    long h9 = f0g9+f1g8+f2g7+f3g6+f4g5+f5g4+f6g3+f7g2+f8g1+f9g0;

    long carry0,carry1,carry2,carry3,carry4,carry5,carry6,carry7,carry8,carry9;

    carry0 = (h0 + ((long)1<<25)) >> 26; h1 += carry0; h0 -= carry0*((long)1<<26);
    carry4 = (h4 + ((long)1<<25)) >> 26; h5 += carry4; h4 -= carry4*((long)1<<26);

    carry1 = (h1 + ((long)1<<24)) >> 25; h2 += carry1; h1 -= carry1*((long)1<<25);
    carry5 = (h5 + ((long)1<<24)) >> 25; h6 += carry5; h5 -= carry5*((long)1<<25);

    carry2 = (h2 + ((long)1<<25)) >> 26; h3 += carry2; h2 -= carry2*((long)1<<26);
    carry6 = (h6 + ((long)1<<25)) >> 26; h7 += carry6; h6 -= carry6*((long)1<<26);

    carry3 = (h3 + ((long)1<<24)) >> 25; h4 += carry3; h3 -= carry3*((long)1<<25);
    carry7 = (h7 + ((long)1<<24)) >> 25; h8 += carry7; h7 -= carry7*((long)1<<25);

    carry4 = (h4 + ((long)1<<25)) >> 26; h5 += carry4; h4 -= carry4*((long)1<<26);
    carry8 = (h8 + ((long)1<<25)) >> 26; h9 += carry8; h8 -= carry8*((long)1<<26);

    carry9 = (h9 + ((long)1<<24)) >> 25; h0 += carry9*19; h9 -= carry9*((long)1<<25);

    carry0 = (h0 + ((long)1<<25)) >> 26; h1 += carry0; h0 -= carry0*((long)1<<26);

    h[0]=(int)h0; h[1]=(int)h1; h[2]=(int)h2; h[3]=(int)h3; h[4]=(int)h4;
    h[5]=(int)h5; h[6]=(int)h6; h[7]=(int)h7; h[8]=(int)h8; h[9]=(int)h9;
}

inline void fe_sq(thread int* h, thread const int* f) {
    int f0=f[0],f1=f[1],f2=f[2],f3=f[3],f4=f[4],f5=f[5],f6=f[6],f7=f[7],f8=f[8],f9=f[9];

    int f0_2=2*f0, f1_2=2*f1, f2_2=2*f2, f3_2=2*f3, f4_2=2*f4, f5_2=2*f5, f6_2=2*f6, f7_2=2*f7;
    int f5_38=38*f5, f6_19=19*f6, f7_38=38*f7, f8_19=19*f8, f9_38=38*f9;

    long f0f0=f0*(long)f0, f0f1_2=f0_2*(long)f1, f0f2_2=f0_2*(long)f2, f0f3_2=f0_2*(long)f3,
         f0f4_2=f0_2*(long)f4, f0f5_2=f0_2*(long)f5, f0f6_2=f0_2*(long)f6, f0f7_2=f0_2*(long)f7,
         f0f8_2=f0_2*(long)f8, f0f9_2=f0_2*(long)f9;
    long f1f1_2=f1_2*(long)f1, f1f2_2=f1_2*(long)f2, f1f3_4=f1_2*(long)f3_2, f1f4_2=f1_2*(long)f4,
         f1f5_4=f1_2*(long)f5_2, f1f6_2=f1_2*(long)f6, f1f7_4=f1_2*(long)f7_2, f1f8_2=f1_2*(long)f8,
         f1f9_76=f1_2*(long)f9_38;
    long f2f2=f2*(long)f2, f2f3_2=f2_2*(long)f3, f2f4_2=f2_2*(long)f4, f2f5_2=f2_2*(long)f5,
         f2f6_2=f2_2*(long)f6, f2f7_2=f2_2*(long)f7, f2f8_38=f2_2*(long)f8_19, f2f9_38=f2*(long)f9_38;
    long f3f3_2=f3_2*(long)f3, f3f4_2=f3_2*(long)f4, f3f5_4=f3_2*(long)f5_2, f3f6_2=f3_2*(long)f6,
         f3f7_76=f3_2*(long)f7_38, f3f8_38=f3_2*(long)f8_19, f3f9_76=f3_2*(long)f9_38;
    long f4f4=f4*(long)f4, f4f5_2=f4_2*(long)f5, f4f6_38=f4_2*(long)f6_19, f4f7_38=f4*(long)f7_38,
         f4f8_38=f4_2*(long)f8_19, f4f9_38=f4*(long)f9_38;
    long f5f5_38=f5*(long)f5_38, f5f6_38=f5_2*(long)f6_19, f5f7_76=f5_2*(long)f7_38,
         f5f8_38=f5_2*(long)f8_19, f5f9_76=f5_2*(long)f9_38;
    long f6f6_19=f6*(long)f6_19, f6f7_38=f6*(long)f7_38, f6f8_38=f6_2*(long)f8_19, f6f9_38=f6*(long)f9_38;
    long f7f7_38=f7*(long)f7_38, f7f8_38=f7_2*(long)f8_19, f7f9_76=f7_2*(long)f9_38;
    long f8f8_19=f8*(long)f8_19, f8f9_38=f8*(long)f9_38;
    long f9f9_38=f9*(long)f9_38;

    long h0=f0f0+f1f9_76+f2f8_38+f3f7_76+f4f6_38+f5f5_38;
    long h1=f0f1_2+f2f9_38+f3f8_38+f4f7_38+f5f6_38;
    long h2=f0f2_2+f1f1_2+f3f9_76+f4f8_38+f5f7_76+f6f6_19;
    long h3=f0f3_2+f1f2_2+f4f9_38+f5f8_38+f6f7_38;
    long h4=f0f4_2+f1f3_4+f2f2+f5f9_76+f6f8_38+f7f7_38;
    long h5=f0f5_2+f1f4_2+f2f3_2+f6f9_38+f7f8_38;
    long h6=f0f6_2+f1f5_4+f2f4_2+f3f3_2+f7f9_76+f8f8_19;
    long h7=f0f7_2+f1f6_2+f2f5_2+f3f4_2+f8f9_38;
    long h8=f0f8_2+f1f7_4+f2f6_2+f3f5_4+f4f4+f9f9_38;
    long h9=f0f9_2+f1f8_2+f2f7_2+f3f6_2+f4f5_2;

    long carry0,carry1,carry2,carry3,carry4,carry5,carry6,carry7,carry8,carry9;

    carry0=(h0+((long)1<<25))>>26; h1+=carry0; h0-=carry0*((long)1<<26);
    carry4=(h4+((long)1<<25))>>26; h5+=carry4; h4-=carry4*((long)1<<26);

    carry1=(h1+((long)1<<24))>>25; h2+=carry1; h1-=carry1*((long)1<<25);
    carry5=(h5+((long)1<<24))>>25; h6+=carry5; h5-=carry5*((long)1<<25);

    carry2=(h2+((long)1<<25))>>26; h3+=carry2; h2-=carry2*((long)1<<26);
    carry6=(h6+((long)1<<25))>>26; h7+=carry6; h6-=carry6*((long)1<<26);

    carry3=(h3+((long)1<<24))>>25; h4+=carry3; h3-=carry3*((long)1<<25);
    carry7=(h7+((long)1<<24))>>25; h8+=carry7; h7-=carry7*((long)1<<25);

    carry4=(h4+((long)1<<25))>>26; h5+=carry4; h4-=carry4*((long)1<<26);
    carry8=(h8+((long)1<<25))>>26; h9+=carry8; h8-=carry8*((long)1<<26);

    carry9=(h9+((long)1<<24))>>25; h0+=carry9*19; h9-=carry9*((long)1<<25);

    carry0=(h0+((long)1<<25))>>26; h1+=carry0; h0-=carry0*((long)1<<26);

    h[0]=(int)h0; h[1]=(int)h1; h[2]=(int)h2; h[3]=(int)h3; h[4]=(int)h4;
    h[5]=(int)h5; h[6]=(int)h6; h[7]=(int)h7; h[8]=(int)h8; h[9]=(int)h9;
}

inline void fe_sq2(thread int* h, thread const int* f) {
    // h = 2*f*f -- identical products to fe_sq, then each limb doubled before
    // the same carry chain (ported from libsodium ref10 fe25519_sq2).
    int f0=f[0],f1=f[1],f2=f[2],f3=f[3],f4=f[4],f5=f[5],f6=f[6],f7=f[7],f8=f[8],f9=f[9];

    int f0_2=2*f0, f1_2=2*f1, f2_2=2*f2, f3_2=2*f3, f4_2=2*f4, f5_2=2*f5, f6_2=2*f6, f7_2=2*f7;
    int f5_38=38*f5, f6_19=19*f6, f7_38=38*f7, f8_19=19*f8, f9_38=38*f9;

    long f0f0=f0*(long)f0, f0f1_2=f0_2*(long)f1, f0f2_2=f0_2*(long)f2, f0f3_2=f0_2*(long)f3,
         f0f4_2=f0_2*(long)f4, f0f5_2=f0_2*(long)f5, f0f6_2=f0_2*(long)f6, f0f7_2=f0_2*(long)f7,
         f0f8_2=f0_2*(long)f8, f0f9_2=f0_2*(long)f9;
    long f1f1_2=f1_2*(long)f1, f1f2_2=f1_2*(long)f2, f1f3_4=f1_2*(long)f3_2, f1f4_2=f1_2*(long)f4,
         f1f5_4=f1_2*(long)f5_2, f1f6_2=f1_2*(long)f6, f1f7_4=f1_2*(long)f7_2, f1f8_2=f1_2*(long)f8,
         f1f9_76=f1_2*(long)f9_38;
    long f2f2=f2*(long)f2, f2f3_2=f2_2*(long)f3, f2f4_2=f2_2*(long)f4, f2f5_2=f2_2*(long)f5,
         f2f6_2=f2_2*(long)f6, f2f7_2=f2_2*(long)f7, f2f8_38=f2_2*(long)f8_19, f2f9_38=f2*(long)f9_38;
    long f3f3_2=f3_2*(long)f3, f3f4_2=f3_2*(long)f4, f3f5_4=f3_2*(long)f5_2, f3f6_2=f3_2*(long)f6,
         f3f7_76=f3_2*(long)f7_38, f3f8_38=f3_2*(long)f8_19, f3f9_76=f3_2*(long)f9_38;
    long f4f4=f4*(long)f4, f4f5_2=f4_2*(long)f5, f4f6_38=f4_2*(long)f6_19, f4f7_38=f4*(long)f7_38,
         f4f8_38=f4_2*(long)f8_19, f4f9_38=f4*(long)f9_38;
    long f5f5_38=f5*(long)f5_38, f5f6_38=f5_2*(long)f6_19, f5f7_76=f5_2*(long)f7_38,
         f5f8_38=f5_2*(long)f8_19, f5f9_76=f5_2*(long)f9_38;
    long f6f6_19=f6*(long)f6_19, f6f7_38=f6*(long)f7_38, f6f8_38=f6_2*(long)f8_19, f6f9_38=f6*(long)f9_38;
    long f7f7_38=f7*(long)f7_38, f7f8_38=f7_2*(long)f8_19, f7f9_76=f7_2*(long)f9_38;
    long f8f8_19=f8*(long)f8_19, f8f9_38=f8*(long)f9_38;
    long f9f9_38=f9*(long)f9_38;

    long h0=f0f0+f1f9_76+f2f8_38+f3f7_76+f4f6_38+f5f5_38;
    long h1=f0f1_2+f2f9_38+f3f8_38+f4f7_38+f5f6_38;
    long h2=f0f2_2+f1f1_2+f3f9_76+f4f8_38+f5f7_76+f6f6_19;
    long h3=f0f3_2+f1f2_2+f4f9_38+f5f8_38+f6f7_38;
    long h4=f0f4_2+f1f3_4+f2f2+f5f9_76+f6f8_38+f7f7_38;
    long h5=f0f5_2+f1f4_2+f2f3_2+f6f9_38+f7f8_38;
    long h6=f0f6_2+f1f5_4+f2f4_2+f3f3_2+f7f9_76+f8f8_19;
    long h7=f0f7_2+f1f6_2+f2f5_2+f3f4_2+f8f9_38;
    long h8=f0f8_2+f1f7_4+f2f6_2+f3f5_4+f4f4+f9f9_38;
    long h9=f0f9_2+f1f8_2+f2f7_2+f3f6_2+f4f5_2;

    h0+=h0; h1+=h1; h2+=h2; h3+=h3; h4+=h4; h5+=h5; h6+=h6; h7+=h7; h8+=h8; h9+=h9;

    long carry0,carry1,carry2,carry3,carry4,carry5,carry6,carry7,carry8,carry9;

    carry0=(h0+((long)1<<25))>>26; h1+=carry0; h0-=carry0*((long)1<<26);
    carry4=(h4+((long)1<<25))>>26; h5+=carry4; h4-=carry4*((long)1<<26);

    carry1=(h1+((long)1<<24))>>25; h2+=carry1; h1-=carry1*((long)1<<25);
    carry5=(h5+((long)1<<24))>>25; h6+=carry5; h5-=carry5*((long)1<<25);

    carry2=(h2+((long)1<<25))>>26; h3+=carry2; h2-=carry2*((long)1<<26);
    carry6=(h6+((long)1<<25))>>26; h7+=carry6; h6-=carry6*((long)1<<26);

    carry3=(h3+((long)1<<24))>>25; h4+=carry3; h3-=carry3*((long)1<<25);
    carry7=(h7+((long)1<<24))>>25; h8+=carry7; h7-=carry7*((long)1<<25);

    carry4=(h4+((long)1<<25))>>26; h5+=carry4; h4-=carry4*((long)1<<26);
    carry8=(h8+((long)1<<25))>>26; h9+=carry8; h8-=carry8*((long)1<<26);

    carry9=(h9+((long)1<<24))>>25; h0+=carry9*19; h9-=carry9*((long)1<<25);

    carry0=(h0+((long)1<<25))>>26; h1+=carry0; h0-=carry0*((long)1<<26);

    h[0]=(int)h0; h[1]=(int)h1; h[2]=(int)h2; h[3]=(int)h3; h[4]=(int)h4;
    h[5]=(int)h5; h[6]=(int)h6; h[7]=(int)h7; h[8]=(int)h8; h[9]=(int)h9;
}

inline int fe_isnegative(thread const int* f) {
    uchar s[32];
    fe_tobytes(s, f);
    return s[0] & 1;
}

// Inversion via z^(p-2), using the classical 255-squarings/11-multiplications
// addition chain (ported from filippo.io/edwards25519's Invert(), which
// expresses the same chain over a different limb representation).
inline void fe_invert(thread int* out, thread const int* z) {
    int z2[10], t[10], z9[10], z11[10], z2_5_0[10], z2_10_0[10], z2_20_0[10], z2_50_0[10], z2_100_0[10];

    fe_sq(z2, z);                 // 2
    fe_sq(t, z2);                 // 4
    fe_sq(t, t);                  // 8
    fe_mul(z9, t, z);             // 9
    fe_mul(z11, z9, z2);          // 11
    fe_sq(t, z11);                // 22
    fe_mul(z2_5_0, t, z9);        // 2^5-2^0 = 31

    fe_sq(t, z2_5_0);
    for (int i = 0; i < 4; i++) fe_sq(t, t);   // 2^10-2^5
    fe_mul(z2_10_0, t, z2_5_0);   // 2^10-2^0

    fe_sq(t, z2_10_0);
    for (int i = 0; i < 9; i++) fe_sq(t, t);   // 2^20-2^10
    fe_mul(z2_20_0, t, z2_10_0);  // 2^20-2^0

    fe_sq(t, z2_20_0);
    for (int i = 0; i < 19; i++) fe_sq(t, t);  // 2^40-2^20
    fe_mul(t, t, z2_20_0);        // 2^40-2^0

    fe_sq(t, t);
    for (int i = 0; i < 9; i++) fe_sq(t, t);   // 2^50-2^10
    fe_mul(z2_50_0, t, z2_10_0);  // 2^50-2^0

    fe_sq(t, z2_50_0);
    for (int i = 0; i < 49; i++) fe_sq(t, t);  // 2^100-2^50
    fe_mul(z2_100_0, t, z2_50_0); // 2^100-2^0

    fe_sq(t, z2_100_0);
    for (int i = 0; i < 99; i++) fe_sq(t, t);  // 2^200-2^100
    fe_mul(t, t, z2_100_0);       // 2^200-2^0

    fe_sq(t, t);
    for (int i = 0; i < 49; i++) fe_sq(t, t);  // 2^250-2^50
    fe_mul(t, t, z2_50_0);        // 2^250-2^0

    fe_sq(t, t); fe_sq(t, t); fe_sq(t, t); fe_sq(t, t); fe_sq(t, t); // 2^255-2^5

    fe_mul(out, t, z11);          // 2^255-21 = p-2
}

// ---- Edwards25519 point arithmetic, extended coordinates (X:Y:Z:T) ----
// Ported from libsodium ref10 (ge25519_p2_dbl, ge25519_add_cached,
// ge25519_p1p1_to_p3, ge25519_p3_to_cached), verified against a from-scratch
// Python reference that itself matches the `cryptography` library's real
// ed25519 key derivation.

struct FE { int v[10]; };
struct P3 { FE X, Y, Z, T; };
struct P2 { FE X, Y, Z; };
struct P1P1 { FE X, Y, Z, T; };
struct Cached { FE YplusX, YminusX, Z, T2d; };

inline void FE_add(thread FE& h, thread const FE& f, thread const FE& g) { fe_add(h.v, f.v, g.v); }
inline void FE_sub(thread FE& h, thread const FE& f, thread const FE& g) { fe_sub(h.v, f.v, g.v); }
inline void FE_mul(thread FE& h, thread const FE& f, thread const FE& g) { fe_mul(h.v, f.v, g.v); }
inline void FE_sq(thread FE& h, thread const FE& f)  { fe_sq(h.v, f.v); }
inline void FE_sq2(thread FE& h, thread const FE& f) { fe_sq2(h.v, f.v); }
inline void FE_copy(thread FE& h, thread const FE& f) { for (int i = 0; i < 10; i++) h.v[i] = f.v[i]; }
inline void FE_0(thread FE& h) { for (int i = 0; i < 10; i++) h.v[i] = 0; }
inline void FE_1(thread FE& h) { h.v[0] = 1; for (int i = 1; i < 10; i++) h.v[i] = 0; }
inline void FE_frombytes(thread FE& h, thread const uchar* s) { fe_frombytes(h.v, s); }

// 2*d mod p, libsodium ref10 constants.h ed25519_d2 (limbs copied verbatim).
constant int ED25519_D2[10] = {
    -21827239, -5839606, -30745221, 13898782, 229458, 15978800, -12551817, -6495438, 29715968, 9444199
};

inline void ge_p3_0(thread P3& h) {
    FE_0(h.X); FE_1(h.Y); FE_1(h.Z); FE_0(h.T);
}

inline void ge_p3_to_p2(thread P2& r, thread const P3& p) {
    FE_copy(r.X, p.X); FE_copy(r.Y, p.Y); FE_copy(r.Z, p.Z);
}

inline void ge_p2_dbl(thread P1P1& r, thread const P2& p) {
    FE t0;
    FE_sq(r.X, p.X);
    FE_sq(r.Z, p.Y);
    FE_sq2(r.T, p.Z);
    FE_add(r.Y, p.X, p.Y);
    FE_sq(t0, r.Y);
    FE_add(r.Y, r.Z, r.X);
    FE_sub(r.Z, r.Z, r.X);
    FE_sub(r.X, t0, r.Y);
    FE_sub(r.T, r.T, r.Z);
}

inline void ge_p3_dbl(thread P1P1& r, thread const P3& p) {
    P2 q;
    ge_p3_to_p2(q, p);
    ge_p2_dbl(r, q);
}

inline void ge_p1p1_to_p3(thread P3& r, thread const P1P1& p) {
    FE_mul(r.X, p.X, p.T);
    FE_mul(r.Y, p.Y, p.Z);
    FE_mul(r.Z, p.Z, p.T);
    FE_mul(r.T, p.X, p.Y);
}

inline void ge_p3_to_cached(thread Cached& r, thread const P3& p) {
    FE d2; for (int i = 0; i < 10; i++) d2.v[i] = ED25519_D2[i];
    FE_add(r.YplusX, p.Y, p.X);
    FE_sub(r.YminusX, p.Y, p.X);
    FE_copy(r.Z, p.Z);
    FE_mul(r.T2d, p.T, d2);
}

inline void ge_add_cached(thread P1P1& r, thread const P3& p, thread const Cached& q) {
    FE t0;
    FE_add(r.X, p.Y, p.X);
    FE_sub(r.Y, p.Y, p.X);
    FE_mul(r.Z, r.X, q.YplusX);
    FE_mul(r.Y, r.Y, q.YminusX);
    FE_mul(r.T, q.T2d, p.T);
    FE_mul(r.X, p.Z, q.Z);
    FE_add(t0, r.X, r.X);
    FE_sub(r.X, r.Z, r.Y);
    FE_add(r.Y, r.Z, r.Y);
    FE_add(r.Z, t0, r.T);
    FE_sub(r.T, t0, r.T);
}

inline void ge_p3_tobytes(thread uchar* s, thread const P3& p) {
    FE zinv, x, y;
    fe_invert(zinv.v, p.Z.v);
    FE_mul(x, p.X, zinv);
    FE_mul(y, p.Y, zinv);
    fe_tobytes(s, y.v);
    s[31] ^= (uchar)(fe_isnegative(x.v) << 7);
}

// Plain MSB-first double-and-add scalar multiplication of a fixed base
// point (passed in already as its P3 form). scalar32 is interpreted as a
// 256-bit little-endian integer (bit i = byte i/8, bit i%8), with no
// clamping/reduction applied -- clamping is a Milestone 4 concern, kept
// decoupled from point-arithmetic correctness here.
inline void ge_scalarmult(thread P3& result, thread const uchar* scalar32, thread const P3& base) {
    Cached base_cached;
    ge_p3_to_cached(base_cached, base);

    P3 r;
    ge_p3_0(r);
    for (int i = 255; i >= 0; i--) {
        P1P1 t;
        ge_p3_dbl(t, r);
        ge_p1p1_to_p3(r, t);
        int bit = (scalar32[i >> 3] >> (i & 7)) & 1;
        if (bit) {
            ge_add_cached(t, r, base_cached);
            ge_p1p1_to_p3(r, t);
        }
    }
    result = r;
}

// Precomputed-table scalar multiplication. table holds 256 entries of 64
// bytes each (affine x,y of 2^i*B, i=0..255, Z implicitly 1), generated on
// the host from the same base point validated above. Replaces the
// double-and-add loop's 256 unconditional doublings with pure additions,
// one per set bit (~128 on average) -- since every power-of-two multiple of
// B is already precomputed, a set bit needs only one addition, not a
// doubling-then-maybe-add. Reuses only already-tested primitives
// (ge_add_cached, ge_p1p1_to_p3, ge_p3_0, FE_add/sub/mul/1/frombytes); the
// only new logic is unpacking a table entry and building its Cached form
// with Z fixed to 1, tested against the same oracle as the double-and-add
// version in test_point.py.
inline void ge_scalarmult_table(thread P3& result, thread const uchar* scalar32, constant uchar* table) {
    FE d2; for (int i = 0; i < 10; i++) d2.v[i] = ED25519_D2[i];

    P3 r;
    ge_p3_0(r);
    for (int i = 0; i < 256; i++) {
        int bit = (scalar32[i >> 3] >> (i & 7)) & 1;
        if (!bit) continue;

        constant uchar* entry = table + i * 64;
        uchar xb[32], yb[32];
        for (int k = 0; k < 32; k++) { xb[k] = entry[k]; yb[k] = entry[32+k]; }
        FE x, y;
        FE_frombytes(x, xb);
        FE_frombytes(y, yb);

        Cached c;
        FE_add(c.YplusX, y, x);
        FE_sub(c.YminusX, y, x);
        FE_1(c.Z);
        FE xy;
        FE_mul(xy, x, y);
        FE_mul(c.T2d, xy, d2);

        P1P1 t;
        ge_add_cached(t, r, c);
        ge_p1p1_to_p3(r, t);
    }
    result = r;
}

// ---- test kernels: batched, one field element (or pair) per thread id ----

inline void copy32(thread uchar* dst, device const uchar* src) {
    for (int i = 0; i < 32; i++) dst[i] = src[i];
}

kernel void k_fe_add(device const uchar* a [[buffer(0)]],
                      device const uchar* b [[buffer(1)]],
                      device uchar* out [[buffer(2)]],
                      uint id [[thread_position_in_grid]]) {
    uchar la[32], lb[32], lo[32];
    copy32(la, a + id*32);
    copy32(lb, b + id*32);
    int fa[10], fb[10], fh[10];
    fe_frombytes(fa, la);
    fe_frombytes(fb, lb);
    fe_add(fh, fa, fb);
    fe_tobytes(lo, fh);
    for (int i = 0; i < 32; i++) out[id*32 + i] = lo[i];
}

kernel void k_fe_sub(device const uchar* a [[buffer(0)]],
                      device const uchar* b [[buffer(1)]],
                      device uchar* out [[buffer(2)]],
                      uint id [[thread_position_in_grid]]) {
    uchar la[32], lb[32], lo[32];
    copy32(la, a + id*32);
    copy32(lb, b + id*32);
    int fa[10], fb[10], fh[10];
    fe_frombytes(fa, la);
    fe_frombytes(fb, lb);
    fe_sub(fh, fa, fb);
    fe_tobytes(lo, fh);
    for (int i = 0; i < 32; i++) out[id*32 + i] = lo[i];
}

kernel void k_fe_mul(device const uchar* a [[buffer(0)]],
                      device const uchar* b [[buffer(1)]],
                      device uchar* out [[buffer(2)]],
                      uint id [[thread_position_in_grid]]) {
    uchar la[32], lb[32], lo[32];
    copy32(la, a + id*32);
    copy32(lb, b + id*32);
    int fa[10], fb[10], fh[10];
    fe_frombytes(fa, la);
    fe_frombytes(fb, lb);
    fe_mul(fh, fa, fb);
    fe_tobytes(lo, fh);
    for (int i = 0; i < 32; i++) out[id*32 + i] = lo[i];
}

kernel void k_fe_sq(device const uchar* a [[buffer(0)]],
                     device uchar* out [[buffer(1)]],
                     uint id [[thread_position_in_grid]]) {
    uchar la[32], lo[32];
    copy32(la, a + id*32);
    int fa[10], fh[10];
    fe_frombytes(fa, la);
    fe_sq(fh, fa);
    fe_tobytes(lo, fh);
    for (int i = 0; i < 32; i++) out[id*32 + i] = lo[i];
}

kernel void k_fe_invert(device const uchar* a [[buffer(0)]],
                         device uchar* out [[buffer(1)]],
                         uint id [[thread_position_in_grid]]) {
    uchar la[32], lo[32];
    copy32(la, a + id*32);
    int fa[10], fh[10];
    fe_frombytes(fa, la);
    fe_invert(fh, fa);
    fe_tobytes(lo, fh);
    for (int i = 0; i < 32; i++) out[id*32 + i] = lo[i];
}

kernel void k_fe_roundtrip(device const uchar* a [[buffer(0)]],
                            device uchar* out [[buffer(1)]],
                            uint id [[thread_position_in_grid]]) {
    uchar la[32], lo[32];
    copy32(la, a + id*32);
    int fa[10];
    fe_frombytes(fa, la);
    fe_tobytes(lo, fa);
    for (int i = 0; i < 32; i++) out[id*32 + i] = lo[i];
}

// Standard Ed25519 base point B, independently derived and cross-validated
// against the `cryptography` library (see edwards_ref.py).
constant uchar BASE_X[32] = {
    0x1a, 0xd5, 0x25, 0x8f, 0x60, 0x2d, 0x56, 0xc9, 0xb2, 0xa7, 0x25, 0x95, 0x60, 0xc7, 0x2c, 0x69,
    0x5c, 0xdc, 0xd6, 0xfd, 0x31, 0xe2, 0xa4, 0xc0, 0xfe, 0x53, 0x6e, 0xcd, 0xd3, 0x36, 0x69, 0x21
};
constant uchar BASE_Y[32] = {
    0x58, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
    0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66
};

// ---- SHA-512, single-block-optimized for exactly 32-byte inputs ----
// Round constants and algorithm ported verbatim from Go's standard library
// (crypto/internal/fips140/sha512/sha512block.go), FIPS 180-4.

constant ulong SHA512_K[80] = {
    0x428a2f98d728ae22UL,
    0x7137449123ef65cdUL,
    0xb5c0fbcfec4d3b2fUL,
    0xe9b5dba58189dbbcUL,
    0x3956c25bf348b538UL,
    0x59f111f1b605d019UL,
    0x923f82a4af194f9bUL,
    0xab1c5ed5da6d8118UL,
    0xd807aa98a3030242UL,
    0x12835b0145706fbeUL,
    0x243185be4ee4b28cUL,
    0x550c7dc3d5ffb4e2UL,
    0x72be5d74f27b896fUL,
    0x80deb1fe3b1696b1UL,
    0x9bdc06a725c71235UL,
    0xc19bf174cf692694UL,
    0xe49b69c19ef14ad2UL,
    0xefbe4786384f25e3UL,
    0x0fc19dc68b8cd5b5UL,
    0x240ca1cc77ac9c65UL,
    0x2de92c6f592b0275UL,
    0x4a7484aa6ea6e483UL,
    0x5cb0a9dcbd41fbd4UL,
    0x76f988da831153b5UL,
    0x983e5152ee66dfabUL,
    0xa831c66d2db43210UL,
    0xb00327c898fb213fUL,
    0xbf597fc7beef0ee4UL,
    0xc6e00bf33da88fc2UL,
    0xd5a79147930aa725UL,
    0x06ca6351e003826fUL,
    0x142929670a0e6e70UL,
    0x27b70a8546d22ffcUL,
    0x2e1b21385c26c926UL,
    0x4d2c6dfc5ac42aedUL,
    0x53380d139d95b3dfUL,
    0x650a73548baf63deUL,
    0x766a0abb3c77b2a8UL,
    0x81c2c92e47edaee6UL,
    0x92722c851482353bUL,
    0xa2bfe8a14cf10364UL,
    0xa81a664bbc423001UL,
    0xc24b8b70d0f89791UL,
    0xc76c51a30654be30UL,
    0xd192e819d6ef5218UL,
    0xd69906245565a910UL,
    0xf40e35855771202aUL,
    0x106aa07032bbd1b8UL,
    0x19a4c116b8d2d0c8UL,
    0x1e376c085141ab53UL,
    0x2748774cdf8eeb99UL,
    0x34b0bcb5e19b48a8UL,
    0x391c0cb3c5c95a63UL,
    0x4ed8aa4ae3418acbUL,
    0x5b9cca4f7763e373UL,
    0x682e6ff3d6b2b8a3UL,
    0x748f82ee5defb2fcUL,
    0x78a5636f43172f60UL,
    0x84c87814a1f0ab72UL,
    0x8cc702081a6439ecUL,
    0x90befffa23631e28UL,
    0xa4506cebde82bde9UL,
    0xbef9a3f7b2c67915UL,
    0xc67178f2e372532bUL,
    0xca273eceea26619cUL,
    0xd186b8c721c0c207UL,
    0xeada7dd6cde0eb1eUL,
    0xf57d4f7fee6ed178UL,
    0x06f067aa72176fbaUL,
    0x0a637dc5a2c898a6UL,
    0x113f9804bef90daeUL,
    0x1b710b35131c471bUL,
    0x28db77f523047d84UL,
    0x32caab7b40c72493UL,
    0x3c9ebe0a15c9bebcUL,
    0x431d67c49c100d4cUL,
    0x4cc5d4becb3e42b6UL,
    0x597f299cfc657e2aUL,
    0x5fcb6fab3ad6faecUL,
    0x6c44198c4a475817UL
};

inline ulong rotr64(ulong x, uint n) {
    return (x >> n) | (x << (64 - n));
}

// Hashes exactly 32 bytes (one padded 128-byte SHA-512 block) and writes the
// 64-byte digest to out64.
inline void sha512_32(thread uchar* out64, thread const uchar* msg32) {
    uchar block[128];
    for (int i = 0; i < 32; i++) block[i] = msg32[i];
    block[32] = 0x80;
    for (int i = 33; i < 126; i++) block[i] = 0;
    block[126] = 0x01;  // bit length 256 = 0x100, big-endian in the last 16 bytes
    block[127] = 0x00;

    ulong h0 = 0x6a09e667f3bcc908UL, h1 = 0xbb67ae8584caa73bUL, h2 = 0x3c6ef372fe94f82bUL, h3 = 0xa54ff53a5f1d36f1UL;
    ulong h4 = 0x510e527fade682d1UL, h5 = 0x9b05688c2b3e6c1fUL, h6 = 0x1f83d9abfb41bd6bUL, h7 = 0x5be0cd19137e2179UL;

    ulong w[80];
    for (int i = 0; i < 16; i++) {
        int j = i * 8;
        w[i] = (ulong)block[j]<<56 | (ulong)block[j+1]<<48 | (ulong)block[j+2]<<40 | (ulong)block[j+3]<<32 |
               (ulong)block[j+4]<<24 | (ulong)block[j+5]<<16 | (ulong)block[j+6]<<8  | (ulong)block[j+7];
    }
    for (int i = 16; i < 80; i++) {
        ulong v1 = w[i-2];
        ulong t1 = rotr64(v1, 19) ^ rotr64(v1, 61) ^ (v1 >> 6);
        ulong v2 = w[i-15];
        ulong t2 = rotr64(v2, 1) ^ rotr64(v2, 8) ^ (v2 >> 7);
        w[i] = t1 + w[i-7] + t2 + w[i-16];
    }

    ulong a=h0, b=h1, c=h2, d=h3, e=h4, f=h5, g=h6, h=h7;
    for (int i = 0; i < 80; i++) {
        ulong t1 = h + (rotr64(e,14) ^ rotr64(e,18) ^ rotr64(e,41)) + ((e & f) ^ (~e & g)) + SHA512_K[i] + w[i];
        ulong t2 = (rotr64(a,28) ^ rotr64(a,34) ^ rotr64(a,39)) + ((a & b) ^ (a & c) ^ (b & c));
        h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }

    h0 += a; h1 += b; h2 += c; h3 += d; h4 += e; h5 += f; h6 += g; h7 += h;

    ulong hs[8] = {h0, h1, h2, h3, h4, h5, h6, h7};
    for (int i = 0; i < 8; i++) {
        ulong v = hs[i];
        out64[i*8+0] = (uchar)(v >> 56);
        out64[i*8+1] = (uchar)(v >> 48);
        out64[i*8+2] = (uchar)(v >> 40);
        out64[i*8+3] = (uchar)(v >> 32);
        out64[i*8+4] = (uchar)(v >> 24);
        out64[i*8+5] = (uchar)(v >> 16);
        out64[i*8+6] = (uchar)(v >> 8);
        out64[i*8+7] = (uchar)(v);
    }
}

kernel void k_sha512_32(device const uchar* msg [[buffer(0)]],
                         device uchar* out [[buffer(1)]],
                         uint id [[thread_position_in_grid]]) {
    uchar lmsg[32], lout[64];
    copy32(lmsg, msg + id*32);
    sha512_32(lout, lmsg);
    for (int i = 0; i < 64; i++) out[id*64 + i] = lout[i];
}

inline void ge_base_point(thread P3& base) {
    uchar bx[32], by[32];
    for (int i = 0; i < 32; i++) { bx[i] = BASE_X[i]; by[i] = BASE_Y[i]; }
    FE_frombytes(base.X, bx);
    FE_frombytes(base.Y, by);
    FE_1(base.Z);
    FE_mul(base.T, base.X, base.Y);
}

kernel void k_scalarmult_base(device const uchar* scalar [[buffer(0)]],
                               device uchar* out [[buffer(1)]],
                               uint id [[thread_position_in_grid]]) {
    uchar lscalar[32];
    copy32(lscalar, scalar + id*32);

    P3 base;
    ge_base_point(base);

    P3 result;
    ge_scalarmult(result, lscalar, base);

    uchar lo[32];
    ge_p3_tobytes(lo, result);
    for (int i = 0; i < 32; i++) out[id*32 + i] = lo[i];
}

// Same as k_scalarmult_base but via the precomputed table, for direct
// testing against the identical oracle used for the double-and-add version.
kernel void k_scalarmult_base_table(device const uchar* scalar [[buffer(0)]],
                                     constant uchar* table [[buffer(1)]],
                                     device uchar* out [[buffer(2)]],
                                     uint id [[thread_position_in_grid]]) {
    uchar lscalar[32];
    copy32(lscalar, scalar + id*32);

    P3 result;
    ge_scalarmult_table(result, lscalar, table);

    uchar lo[32];
    ge_p3_tobytes(lo, result);
    for (int i = 0; i < 32; i++) out[id*32 + i] = lo[i];
}

// ---- Full derivation: seed -> SHA-512 -> clamp -> scalar*B -> compressed pubkey ----
// This is the real correctness gate: it's tested end-to-end against the
// `cryptography` library's actual Ed25519 key derivation, independent of how
// the internals above happen to be split into layers.

inline void ed25519_derive_pubkey(thread uchar* pubkey32, thread const uchar* seed32, constant uchar* table) {
    uchar h[64];
    sha512_32(h, seed32);

    uchar scalar[32];
    for (int i = 0; i < 32; i++) scalar[i] = h[i];
    scalar[0] &= 248;
    scalar[31] &= 127;
    scalar[31] |= 64;

    P3 result;
    ge_scalarmult_table(result, scalar, table);

    ge_p3_tobytes(pubkey32, result);
}

kernel void k_derive_pubkey(device const uchar* seed [[buffer(0)]],
                             constant uchar* table [[buffer(1)]],
                             device uchar* out [[buffer(2)]],
                             uint id [[thread_position_in_grid]]) {
    uchar lseed[32], lout[32];
    copy32(lseed, seed + id*32);
    ed25519_derive_pubkey(lout, lseed, table);
    for (int i = 0; i < 32; i++) out[id*32 + i] = lout[i];
}

// ---- base64 encoding of the 51-byte SSH wire-format public key blob ----
// 51 bytes is an exact multiple of 3, so this is plain unpadded base64 with
// no partial-group edge case to get wrong.

constant uchar B64_ALPHABET[64] = {
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
    'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
    'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
    'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/'
};

inline void base64_encode_51(thread uchar* out68, thread const uchar* in51) {
    int oi = 0;
    for (int i = 0; i < 51; i += 3) {
        uint n = ((uint)in51[i] << 16) | ((uint)in51[i+1] << 8) | (uint)in51[i+2];
        out68[oi++] = B64_ALPHABET[(n >> 18) & 0x3F];
        out68[oi++] = B64_ALPHABET[(n >> 12) & 0x3F];
        out68[oi++] = B64_ALPHABET[(n >> 6) & 0x3F];
        out68[oi++] = B64_ALPHABET[n & 0x3F];
    }
}

kernel void k_base64_51(device const uchar* in [[buffer(0)]],
                         device uchar* out [[buffer(1)]],
                         uint id [[thread_position_in_grid]]) {
    uchar lin[51], lout[68];
    for (int i = 0; i < 51; i++) lin[i] = in[id*51 + i];
    base64_encode_51(lout, lin);
    for (int i = 0; i < 68; i++) out[id*68 + i] = lout[i];
}

// ---- grind kernel: derive, encode, check suffix against up to 8 fixed-length targets ----
// All targets must share one length (true for our actual use: /harald,
// /Harald, +harald, +Harald are all 7 chars) -- kept deliberately simple
// rather than building a general variable-length matcher nothing else needs.

#define MAX_TARGETS 8
#define TARGET_LEN 7

kernel void k_grind(device const uchar* seeds [[buffer(0)]],
                     constant uchar* table [[buffer(1)]],
                     constant uchar* targets [[buffer(2)]],       // num_targets * TARGET_LEN bytes
                     constant uint& num_targets [[buffer(3)]],
                     device atomic_uint* match_count [[buffer(4)]],
                     device uchar* match_seeds [[buffer(5)]],      // max_matches * 32 bytes
                     constant uint& max_matches [[buffer(6)]],
                     uint id [[thread_position_in_grid]]) {
    uchar lseed[32], pub[32];
    copy32(lseed, seeds + id*32);
    ed25519_derive_pubkey(pub, lseed, table);

    uchar prefix[19];
    { uchar tmp[19] = {0,0,0,11,'s','s','h','-','e','d','2','5','5','1','9',0,0,0,32}; for (int i=0;i<19;i++) prefix[i]=tmp[i]; }
    uchar wire[51];
    for (int i = 0; i < 19; i++) wire[i] = prefix[i];
    for (int i = 0; i < 32; i++) wire[19+i] = pub[i];

    uchar b64[68];
    base64_encode_51(b64, wire);

    for (uint t = 0; t < num_targets && t < MAX_TARGETS; t++) {
        bool match = true;
        for (uint k = 0; k < TARGET_LEN; k++) {
            if (b64[68 - TARGET_LEN + k] != targets[t * TARGET_LEN + k]) { match = false; break; }
        }
        if (match) {
            uint idx = atomic_fetch_add_explicit(match_count, 1u, memory_order_relaxed);
            if (idx < max_matches) {
                for (int i = 0; i < 32; i++) match_seeds[idx*32 + i] = lseed[i];
            }
            break;
        }
    }
}
