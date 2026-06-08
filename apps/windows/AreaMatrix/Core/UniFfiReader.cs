using System.Buffers.Binary;
using System.Text;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Core;

internal sealed class UniFfiReader
{
    private readonly byte[] bytes;
    private int offset;

    public UniFfiReader(byte[] bytes)
    {
        this.bytes = bytes;
    }

    public bool IsAtEnd => offset == bytes.Length;

    public byte ReadByte()
    {
        EnsureAvailable(1);
        return bytes[offset++];
    }

    public bool ReadBool()
    {
        return ReadByte() != 0;
    }

    public int ReadInt32()
    {
        EnsureAvailable(4);
        int value = BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(offset, 4));
        offset += 4;
        return value;
    }

    public long ReadInt64()
    {
        EnsureAvailable(8);
        long value = BinaryPrimitives.ReadInt64BigEndian(bytes.AsSpan(offset, 8));
        offset += 8;
        return value;
    }

    public float ReadSingle()
    {
        EnsureAvailable(4);
        int bits = BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(offset, 4));
        offset += 4;
        return BitConverter.Int32BitsToSingle(bits);
    }

    public string ReadString()
    {
        int length = ReadInt32();
        EnsureAvailable(length);
        string value = Encoding.UTF8.GetString(bytes, offset, length);
        offset += length;
        return value;
    }

    private void EnsureAvailable(int length)
    {
        if (length < 0 || offset + length > bytes.Length)
        {
            throw new WindowsRepositoryCoreException(
                WindowsRepositoryErrorKind.Config,
                "AreaMatrix Core returned truncated binding data.");
        }
    }
}
