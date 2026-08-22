using Murmur.Dictionary;
using Murmur.Speech;

namespace Murmur.App;

/// <summary>
/// A headless check that the published binary actually works.
/// </summary>
/// <remarks>
/// Run in CI against the real single-file executable. It cannot show a window on a runner, so
/// it verifies the things that only break <i>after</i> publishing: assemblies resolving out
/// of the bundle, native libraries extracting, and paths resolving against
/// <c>AppContext.BaseDirectory</c> rather than the current directory.
/// </remarks>
public static class SelfTest
{
    /// <summary>Runs the checks.</summary>
    /// <returns>0 if everything passed.</returns>
    public static int Run()
    {
        var failures = 0;

        // The dictionary engine, end to end, with no UI involved.
        var corrector = new DictionaryCorrector([DictionaryEntry.Correction("cloud code", "Claude Code")]);
        var (text, applied) = corrector.Apply("I use CloudCode daily.");

        failures += Check("dictionary rewrites glued words",
            text == "I use Claude Code daily." && applied.Count == 1);

        failures += Check("dictionary leaves similar words alone",
            corrector.Apply("Cloudflare is fine.").Text == "Cloudflare is fine.");

        // Model discovery must not throw when nothing is installed — a fresh machine has no
        // model yet, and that has to be a friendly message rather than a crash on launch.
        var located = ParakeetTranscriber.Locate();
        Console.WriteLine($"  model: {located ?? "(not installed — expected on a clean runner)"}");

        failures += Check("model search paths resolve",
            ParakeetTranscriber.DefaultSearchPaths().All(Path.IsPathRooted));

        Console.WriteLine(failures == 0 ? "self-test: PASS" : $"self-test: {failures} FAILED");
        return failures == 0 ? 0 : 1;
    }

    private static int Check(string name, bool passed)
    {
        Console.WriteLine($"  [{(passed ? "ok" : "FAIL")}] {name}");
        return passed ? 0 : 1;
    }
}
