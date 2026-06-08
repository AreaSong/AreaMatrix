using System.Buffers.Binary;
using System.Text;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Core;

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

    public string ReadStringOrRemainingUtf8()
    {
        if (CanReadLengthPrefixedString())
        {
            return ReadString();
        }

        string value = Encoding.UTF8.GetString(bytes, offset, bytes.Length - offset);
        offset = bytes.Length;
        return value;
    }

    private void EnsureAvailable(int length)
    {
        if (length < 0 || offset + length > bytes.Length)
        {
            throw new LinuxRepositoryCoreException(
                LinuxRepositoryErrorKind.Config,
                "AreaMatrix Core returned truncated binding data.");
        }
    }

    private bool CanReadLengthPrefixedString()
    {
        if (bytes.Length - offset < 4)
        {
            return false;
        }

        int length = BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(offset, 4));
        return length >= 0 && offset + 4 + length == bytes.Length;
    }
}
