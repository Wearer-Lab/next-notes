using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Murmur.App.Controls;
using Murmur.App.Design;

namespace Murmur.App.Views;

/// <summary>
/// The main window — the front panel of the unit.
/// </summary>
/// <remarks>
/// <para>
/// Laid out the way a deck is: transport and meter across the top on the panel itself, then a
/// recessed well below holding whichever section is selected.
/// </para>
/// <para>
/// Built in code rather than XAML, deliberately. Every value comes from
/// <see cref="Tokens"/>, and XAML makes it far too easy to type a literal <c>Margin="12,8"</c>
/// that silently escapes the design system. In C# a stray number is visible in review.
/// </para>
/// </remarks>
public sealed class MainWindow : Window
{
    private readonly TransportKey _recordKey;
    private readonly Lamp _recordLamp;
    private readonly VuMeter _meter;
    private readonly TextBlock _counter;
    private readonly ContentControl _sectionHost;
    private readonly TransportKey _transcriptionsKey;
    private readonly TransportKey _dictionaryKey;

    private bool _isRecording;

    /// <summary>Builds the window.</summary>
    public MainWindow()
    {
        Title = "Murmur";
        MinWidth = 720;
        MinHeight = 520;
        Width = 880;
        Height = 640;
        Background = Tokens.Brushes.Chassis;

        _recordKey = new TransportKey { Content = "RECORD" };
        _recordKey.Click += (_, _) => ToggleRecording();

        _recordLamp = new Lamp { LampColor = Tokens.Colors.Record };

        _meter = new VuMeter { Width = 168, Height = 54 };

        _counter = new TextBlock
        {
            Text = "00:00",
            FontFamily = Tokens.Fonts.Mono,
            FontSize = Tokens.Fonts.CounterLarge,
            Foreground = Tokens.Brushes.InkOnDeck,
        };

        _transcriptionsKey = new TransportKey { Content = "TRANSCRIPTIONS", IsEngaged = true };
        _dictionaryKey = new TransportKey { Content = "DICTIONARY" };
        _transcriptionsKey.Click += (_, _) => ShowSection(transcriptions: true);
        _dictionaryKey.Click += (_, _) => ShowSection(transcriptions: false);

        _sectionHost = new ContentControl { Content = BuildEmptyState("NO RECORDINGS", "Press Record to start.") };

        Content = BuildLayout();
    }

    private DockPanel BuildLayout()
    {
        var root = new DockPanel { Margin = new Thickness(Tokens.Space.Roomy) };

        var transport = BuildTransportPanel();
        DockPanel.SetDock(transport, Dock.Top);
        root.Children.Add(transport);

        var keys = BuildSectionKeys();
        DockPanel.SetDock(keys, Dock.Top);
        root.Children.Add(keys);

        root.Children.Add(BuildWell(_sectionHost));
        return root;
    }

    /// <summary>Record/stop, the record lamp, the level meter and the tape counter.</summary>
    private BrushedPanel BuildTransportPanel()
    {
        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = Tokens.Space.Wide,
            Margin = new Thickness(Tokens.Space.Roomy),
        };

        var recordGroup = Labelled("TRANSPORT", new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = Tokens.Space.Snug,
            Children =
            {
                _recordKey,
                new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Spacing = Tokens.Space.Tight,
                    VerticalAlignment = VerticalAlignment.Center,
                    Children = { _recordLamp, new Silkscreen { Text = "REC" } },
                },
            },
        });

        row.Children.Add(recordGroup);
        row.Children.Add(Labelled("LEVEL", _meter));
        row.Children.Add(Labelled("COUNTER", Deck(_counter)));

        row.Children.Add(new Vents
        {
            Count = 8,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(Tokens.Space.Wide, 0, 0, 0),
        });

        return new BrushedPanel { Child = row, Margin = new Thickness(0, 0, 0, Tokens.Space.Base) };
    }

    private StackPanel BuildSectionKeys() => new StackPanel
    {
        Orientation = Orientation.Horizontal,
        Spacing = Tokens.Space.Snug,
        Margin = new Thickness(0, 0, 0, Tokens.Space.Base),
        Children = { _transcriptionsKey, _dictionaryKey },
    };

    /// <summary>A recessed well cut into the panel — content sits inside it.</summary>
    private static Border BuildWell(Control content) => new Border
    {
        Background = Tokens.Brushes.Well,
        CornerRadius = new CornerRadius(Tokens.Radius.Panel),
        BorderBrush = new SolidColorBrush(Tokens.Colors.Seam, 0.55),
        BorderThickness = new Thickness(Tokens.Border.Hairline),
        Padding = new Thickness(Tokens.Space.Hair),
        Child = content,
    };

    /// <summary>The dark readout window of a tape deck.</summary>
    private static Border Deck(Control content) => new Border
    {
        Background = Tokens.Brushes.Deck,
        CornerRadius = new CornerRadius(Tokens.Radius.Panel),
        BorderBrush = new SolidColorBrush(Tokens.Colors.Seam),
        BorderThickness = new Thickness(Tokens.Border.Hairline),
        Padding = new Thickness(Tokens.Space.Base, Tokens.Space.Snug),
        Child = content,
    };

    /// <summary>A silkscreen label above a control, the way a panel is printed.</summary>
    private static StackPanel Labelled(string label, Control content) => new StackPanel
    {
        Spacing = Tokens.Space.Tight,
        Children = { new Silkscreen { Text = label }, content },
    };

    private static StackPanel BuildEmptyState(string label, string detail) => new StackPanel
    {
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        Spacing = Tokens.Space.Snug,
        Children =
        {
            new Silkscreen
            {
                Text = label,
                IsLarge = true,
                Foreground = new SolidColorBrush(Tokens.Colors.InkOnDeck, 0.55),
                HorizontalAlignment = HorizontalAlignment.Center,
            },
            new TextBlock
            {
                Text = detail,
                FontFamily = Tokens.Fonts.Grotesque,
                FontSize = Tokens.Fonts.Label,
                Foreground = new SolidColorBrush(Tokens.Colors.InkOnDeck, 0.4),
                HorizontalAlignment = HorizontalAlignment.Center,
            },
        },
    };

    private void ShowSection(bool transcriptions)
    {
        _transcriptionsKey.IsEngaged = transcriptions;
        _dictionaryKey.IsEngaged = !transcriptions;

        _sectionHost.Content = transcriptions
            ? BuildEmptyState("NO RECORDINGS", "Press Record to start.")
            : BuildEmptyState("DICTIONARY EMPTY", "Add words it keeps getting wrong.");
    }

    /// <summary>Toggles recording. Exposed for headless tests.</summary>
    public void ToggleRecording()
    {
        _isRecording = !_isRecording;

        _recordKey.Content = _isRecording ? "STOP" : "RECORD";
        _recordKey.IsEngaged = _isRecording;
        _recordLamp.IsLit = _isRecording;
        _meter.IsActive = _isRecording;
    }

    /// <summary>Whether the transport is engaged. Exposed for headless tests.</summary>
    public bool IsRecording => _isRecording;

    /// <summary>The record lamp. Exposed for headless tests.</summary>
    public Lamp RecordLamp => _recordLamp;

    /// <summary>The level meter. Exposed for headless tests.</summary>
    public VuMeter Meter => _meter;
}
