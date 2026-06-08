namespace AreaMatrix.Linux.Tests.ChooseRepository;

internal static class TestAssert
{
    public static void Equal<T>(T expected, T actual, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException($"{label}: expected `{expected}` got `{actual}`.");
        }
    }

    public static void True(bool value, string label)
    {
        if (!value)
        {
            throw new InvalidOperationException($"{label}: expected true.");
        }
    }

    public static void False(bool value, string label)
    {
        if (value)
        {
            throw new InvalidOperationException($"{label}: expected false.");
        }
    }

    public static void Null(object? value, string label)
    {
        if (value is not null)
        {
            throw new InvalidOperationException($"{label}: expected null.");
        }
    }

    public static void NotNull(object? value, string label)
    {
        if (value is null)
        {
            throw new InvalidOperationException($"{label}: expected non-null.");
        }
    }

    public static void Empty<T>(IReadOnlyCollection<T> values, string label)
    {
        if (values.Count != 0)
        {
            throw new InvalidOperationException($"{label}: expected empty collection.");
        }
    }

    public static void Contains(string needle, string haystack, string label)
    {
        if (!haystack.Contains(needle, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{label}: expected text to contain `{needle}`.");
        }
    }

    public static void NotContains(string needle, string haystack, string label)
    {
        if (haystack.Contains(needle, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{label}: expected text not to contain `{needle}`.");
        }
    }

    public static void SequenceEqual<T>(IReadOnlyList<T> expected, IReadOnlyList<T> actual, string label)
    {
        if (!expected.SequenceEqual(actual))
        {
            throw new InvalidOperationException(
                $"{label}: expected `{string.Join(", ", expected)}` got `{string.Join(", ", actual)}`.");
        }
    }
}
