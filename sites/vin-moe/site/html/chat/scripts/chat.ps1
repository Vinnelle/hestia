# chat runner for Windows, served at https://chat.vin.moe
#
# Run it in PowerShell with:
#
#   irm https://chat.vin.moe | iex
#
# This script downloads the latest release of chat from GitHub, checks that
# it was signed with chat's release key, runs it, and deletes it again when
# chat exits. It installs nothing, never asks for administrator rights, and
# changes no settings. The only files it leaves behind are ones chat itself
# writes, and chat writes nothing unless you ask it to (:install).
#
# It takes five steps:
#
#   1. Check that this is 64-bit Windows, which the release build needs.
#   2. Download chat-windows-x86_64.exe, with SHA256SUMS and
#      SHA256SUMS.minisig, from the latest release on
#      https://github.com/Vinnelle/chat/releases into a new folder inside
#      your temporary folder.
#   3. Check that SHA256SUMS is signed with chat's release key, the public
#      key in $minisignPub below (the same key as minisign.pub in the chat
#      repository). Releases are signed offline, never on GitHub, so even
#      someone who took over the GitHub account couldn't pass this check.
#      Windows has no built-in way to check this kind of signature, so the
#      check is written out in full further down, in C#.
#   4. Check the downloaded program against its SHA-256 in SHA256SUMS.
#   5. Run chat, and delete the folder when it exits.
#
# If any step fails, the script stops before running anything it downloaded.
#
# It works in Windows PowerShell 5.1, which comes with Windows, and in
# PowerShell 7. To read it before you run it, open
# https://chat.vin.moe/chat.ps1 in a browser. To check that's the
# file PowerShell would get, compare the SHA-256 printed by
#
#   iwr https://chat.vin.moe -OutFile chat.ps1; Get-FileHash chat.ps1
#
# with the one shown on https://chat.vin.moe.

# Everything runs inside "& { ... }", a scope of its own, so the settings it
# changes don't stay in your PowerShell session afterwards. It uses return
# rather than exit to stop early, because exit would close the window that
# ran "irm | iex".
& {
    # Stop at the first error, skip the download progress bar (it makes
    # Windows PowerShell 5.1 download very slowly), and allow TLS 1.2, which
    # GitHub requires and Windows PowerShell 5.1 doesn't always enable.
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    # Where releases come from, and the public half of chat's release key.
    # Only the public half is here: it can check signatures, but it can't
    # make them.
    $repo = 'https://github.com/Vinnelle/chat'
    $minisignPub = 'RWSR+ZdG2DibcI2waaAukeezQJcX5D5BcYHmZ2lOzLVATd2FnlS7YEZB'

    # Print a status line on stderr.
    function Say([string] $text) {
        [Console]::Error.WriteLine("chat: $text")
    }

    # Step 1: this script is for 64-bit Windows. $IsLinux and $IsMacOS only
    # exist in PowerShell 7, so in Windows PowerShell 5.1 they're empty.
    if ($IsMacOS) {
        Say "release builds are for Linux and Windows. To build chat yourself, see $repo"
        return
    }
    if ($IsLinux) {
        Say 'this script is for Windows. On Linux, run: curl -fsSL https://chat.vin.moe | sh'
        return
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        Say "release builds are for 64-bit Windows only. To build chat yourself, see $repo"
        return
    }

    # Step 2: a new folder inside your own temporary folder, %TEMP%, which
    # only you can read.
    $asset = 'chat-windows-x86_64.exe'
    $dir = (New-Item -ItemType Directory (Join-Path ([IO.Path]::GetTempPath()) ('chat.' + [IO.Path]::GetRandomFileName()))).FullName
    # The finally block at the end deletes the folder however this ends.
    try {
        # /releases/latest/download/<name> always points at the newest release.
        Say 'downloading the latest release'
        foreach ($file in $asset, 'SHA256SUMS', 'SHA256SUMS.minisig') {
            Invoke-WebRequest -UseBasicParsing "$repo/releases/latest/download/$file" -OutFile (Join-Path $dir $file)
        }

        # Step 3: the signature. Windows has no Ed25519 or BLAKE2b built in, so
        # the check is written out below in C#, which Add-Type compiles in
        # memory the first time this runs in a session. It needs the libraries
        # that hold BigInteger and SHA512, which have different names in
        # Windows PowerShell and PowerShell 7, so they're found from the types
        # themselves.
        if (-not ('ChatRunner.Minisign' -as [type])) {
            $refs = [Numerics.BigInteger], [Security.Cryptography.SHA512] | ForEach-Object { $_.Assembly.Location }
            Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Numerics;
using System.Security.Cryptography;

namespace ChatRunner
{
    // A minisign signature check with nothing outside .NET. minisign signs
    // the BLAKE2b-512 hash of a file with Ed25519, so Verify hashes the file
    // with BLAKE2b (RFC 7693) and checks the signature with Ed25519
    // (RFC 8032). It only checks: there are no secrets in it, it signs
    // nothing, and it sends nothing anywhere.
    public static class Minisign
    {
        // Ed25519's constants (RFC 8032, section 5.1): the prime p, the order
        // L of the base point, the curve constant d, a square root of -1
        // mod p, and the base point G, whose y is 4/5.
        static readonly BigInteger P = BigInteger.Pow(2, 255) - 19;
        static readonly BigInteger L = BigInteger.Pow(2, 252) + BigInteger.Parse("27742317777372353535851937790883648493");
        static readonly BigInteger D = Mod(-121665 * Inv(121666));
        static readonly BigInteger SqrtM1 = BigInteger.ModPow(2, (P - 1) / 4, P);
        static readonly BigInteger[] G = Point(Mod(4 * Inv(5)), 0);

        // BLAKE2b's initialisation vector, and the order it reads the message
        // words in each round (RFC 7693, sections 2.6 and 2.7).
        static readonly ulong[] IV = {
            0x6a09e667f3bcc908UL, 0xbb67ae8584caa73bUL, 0x3c6ef372fe94f82bUL, 0xa54ff53a5f1d36f1UL,
            0x510e527fade682d1UL, 0x9b05688c2b3e6c1fUL, 0x1f83d9abfb41bd6bUL, 0x5be0cd19137e2179UL
        };

        static readonly byte[] Sigma = {
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
            11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
            7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
            9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
            2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
            12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
            13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
            6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
            10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0
        };

        // pub and sig are the decoded minisign key and signature: two bytes
        // naming the algorithm ("Ed" for the key, "ED" for a signature over a
        // BLAKE2b-512 hash), eight bytes of key id, then the 32-byte key or
        // the 64-byte signature.
        public static bool Verify(byte[] pub, byte[] sig, byte[] data)
        {
            if (pub.Length != 42 || sig.Length != 74 || sig[0] != 'E' || sig[1] != 'D') return false;
            return Ed25519(Slice(pub, 10, 32), Blake2b(data), Slice(sig, 10, 64));
        }

        // Ed25519 verification (RFC 8032, section 5.1.7): decode the public
        // key A and the signature's point R, check that S is below L, hash R,
        // A and the message with SHA-512 to get k, and accept only if [S]G
        // equals R + [k]A.
        static bool Ed25519(byte[] pub, byte[] msg, byte[] sig)
        {
            BigInteger[] a = Decode(pub);
            BigInteger[] r = Decode(Slice(sig, 0, 32));
            BigInteger s = Number(sig, 32, 32);
            if (a == null || r == null || s >= L) return false;
            byte[] input = new byte[64 + msg.Length];
            Array.Copy(sig, 0, input, 0, 32);
            Array.Copy(pub, 0, input, 32, 32);
            Array.Copy(msg, 0, input, 64, msg.Length);
            byte[] h;
            using (SHA512 sha = SHA512.Create()) h = sha.ComputeHash(input);
            BigInteger k = Number(h, 0, 64) % L;
            return Same(Times(s, G), Add(r, Times(k, a)));
        }

        // A copy of part of an array.
        static byte[] Slice(byte[] b, int start, int length)
        {
            byte[] r = new byte[length];
            Array.Copy(b, start, r, 0, length);
            return r;
        }

        // Little-endian bytes as a number. The extra zero byte stops
        // BigInteger reading the top bit as a minus sign.
        static BigInteger Number(byte[] b, int start, int length)
        {
            byte[] le = new byte[length + 1];
            Array.Copy(b, start, le, 0, length);
            return new BigInteger(le);
        }

        // a mod p, never negative.
        static BigInteger Mod(BigInteger a)
        {
            BigInteger r = a % P;
            return r.Sign < 0 ? r + P : r;
        }

        // 1/a mod p, by Fermat's little theorem.
        static BigInteger Inv(BigInteger a)
        {
            return BigInteger.ModPow(Mod(a), P - 2, P);
        }

        // A point stored in 32 bytes: y, with the lowest bit of x in the top
        // bit (RFC 8032, section 5.1.3).
        static BigInteger[] Decode(byte[] b)
        {
            int sign = b[31] >> 7;
            byte[] y = Slice(b, 0, 32);
            y[31] &= 0x7f;
            return Point(Number(y, 0, 32), sign);
        }

        // The point with this y and this lowest bit of x, as extended
        // coordinates (x, y, z, t), or null if there isn't one (RFC 8032,
        // section 5.1.3).
        static BigInteger[] Point(BigInteger y, int sign)
        {
            if (y >= P) return null;
            BigInteger x2 = Mod((y * y - 1) * Inv(D * y * y + 1));
            if (x2.IsZero) return sign == 0 ? new BigInteger[] { 0, y, 1, 0 } : null;
            BigInteger x = BigInteger.ModPow(x2, (P + 3) / 8, P);
            if (!Mod(x * x - x2).IsZero) x = Mod(x * SqrtM1);
            if (!Mod(x * x - x2).IsZero) return null;
            if ((x.IsEven ? 0 : 1) != sign) x = P - x;
            return new BigInteger[] { x, y, 1, Mod(x * y) };
        }

        // Adding two points (RFC 8032, section 5.1.4).
        static BigInteger[] Add(BigInteger[] p, BigInteger[] q)
        {
            BigInteger a = Mod((p[1] - p[0]) * (q[1] - q[0]));
            BigInteger b = Mod((p[1] + p[0]) * (q[1] + q[0]));
            BigInteger c = Mod(2 * p[3] * q[3] * D);
            BigInteger d = Mod(2 * p[2] * q[2]);
            BigInteger e = b - a, f = d - c, g = d + c, h = b + a;
            return new BigInteger[] { Mod(e * f), Mod(g * h), Mod(f * g), Mod(e * h) };
        }

        // Multiplying a point by a number, by doubling and adding.
        static BigInteger[] Times(BigInteger s, BigInteger[] p)
        {
            BigInteger[] q = { 0, 1, 1, 0 };
            for (; s > 0; s >>= 1)
            {
                if (!s.IsEven) q = Add(q, p);
                p = Add(p, p);
            }
            return q;
        }

        // Two points in extended coordinates are the same point when
        // x1 * z2 = x2 * z1 and y1 * z2 = y2 * z1.
        static bool Same(BigInteger[] p, BigInteger[] q)
        {
            return Mod(p[0] * q[2] - q[0] * p[2]).IsZero && Mod(p[1] * q[2] - q[1] * p[2]).IsZero;
        }

        // BLAKE2b-512 with no key (RFC 7693, section 3.3).
        static byte[] Blake2b(byte[] data)
        {
            ulong[] h = (ulong[])IV.Clone();
            h[0] ^= 0x01010040UL;
            int blocks = Math.Max(1, (data.Length + 127) / 128);
            for (int i = 0; i < blocks; i++)
            {
                byte[] block = new byte[128];
                Array.Copy(data, i * 128, block, 0, Math.Min(128, data.Length - i * 128));
                bool last = i == blocks - 1;
                Compress(h, block, last ? (ulong)data.Length : (ulong)(i * 128 + 128), last);
            }
            byte[] digest = new byte[64];
            for (int i = 0; i < 8; i++) Array.Copy(BitConverter.GetBytes(h[i]), 0, digest, i * 8, 8);
            return digest;
        }

        // The compression function F (RFC 7693, section 3.2).
        static void Compress(ulong[] h, byte[] block, ulong t, bool last)
        {
            ulong[] m = new ulong[16];
            ulong[] v = new ulong[16];
            for (int i = 0; i < 16; i++) m[i] = BitConverter.ToUInt64(block, i * 8);
            Array.Copy(h, v, 8);
            Array.Copy(IV, 0, v, 8, 8);
            v[12] ^= t;
            if (last) v[14] = ~v[14];
            for (int r = 0; r < 12; r++)
            {
                int s = r % 10 * 16;
                Mix(v, 0, 4, 8, 12, m[Sigma[s]], m[Sigma[s + 1]]);
                Mix(v, 1, 5, 9, 13, m[Sigma[s + 2]], m[Sigma[s + 3]]);
                Mix(v, 2, 6, 10, 14, m[Sigma[s + 4]], m[Sigma[s + 5]]);
                Mix(v, 3, 7, 11, 15, m[Sigma[s + 6]], m[Sigma[s + 7]]);
                Mix(v, 0, 5, 10, 15, m[Sigma[s + 8]], m[Sigma[s + 9]]);
                Mix(v, 1, 6, 11, 12, m[Sigma[s + 10]], m[Sigma[s + 11]]);
                Mix(v, 2, 7, 8, 13, m[Sigma[s + 12]], m[Sigma[s + 13]]);
                Mix(v, 3, 4, 9, 14, m[Sigma[s + 14]], m[Sigma[s + 15]]);
            }
            for (int i = 0; i < 8; i++) h[i] ^= v[i] ^ v[i + 8];
        }

        // The mixing function G (RFC 7693, section 3.1).
        static void Mix(ulong[] v, int a, int b, int c, int d, ulong x, ulong y)
        {
            v[a] += v[b] + x;
            v[d] = Rotate(v[d] ^ v[a], 32);
            v[c] += v[d];
            v[b] = Rotate(v[b] ^ v[c], 24);
            v[a] += v[b] + y;
            v[d] = Rotate(v[d] ^ v[a], 16);
            v[c] += v[d];
            v[b] = Rotate(v[b] ^ v[c], 63);
        }

        // Rotate right by n bits.
        static ulong Rotate(ulong x, int n)
        {
            return (x >> n) | (x << (64 - n));
        }
    }
}
'@
        }
        # The second line of the .minisig file is the signature in base64.
        # Verify returns true only if SHA256SUMS is signed with chat's release
        # key.
        $sig = [Convert]::FromBase64String((Get-Content (Join-Path $dir 'SHA256SUMS.minisig'))[1])
        $sums = [IO.File]::ReadAllBytes((Join-Path $dir 'SHA256SUMS'))
        if (-not [ChatRunner.Minisign]::Verify([Convert]::FromBase64String($minisignPub), $sig, $sums)) {
            Say "the release signature didn't verify"
            return
        }
        # Step 4: find the program's line in SHA256SUMS, which is now known to
        # be genuine, and compare the hashes. Get-FileHash prints capitals,
        # and -ne ignores case.
        $sum = foreach ($line in Get-Content (Join-Path $dir 'SHA256SUMS')) {
            $hash, $name = $line -split '\s+'
            if ($name -eq $asset) { $hash }
        }
        if (-not $sum) {
            Say "SHA256SUMS has no line for $asset"
            return
        }
        if ((Get-FileHash -Algorithm SHA256 (Join-Path $dir $asset)).Hash -ne $sum) {
            Say "$asset doesn't match SHA256SUMS"
            return
        }

        # Step 5: name it chat.exe, start it with any arguments given to this
        # script, and wait for it to exit. The finally block then deletes the
        # folder, and the program with it.
        $exe = Join-Path $dir 'chat.exe'
        Move-Item (Join-Path $dir $asset) $exe
        Say 'signature and checksum match. Starting chat, which is deleted again when it exits'
        & $exe @args
    } finally {
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
    }
} @args
