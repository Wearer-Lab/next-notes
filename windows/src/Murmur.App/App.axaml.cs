using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Murmur.App.Views;

namespace Murmur.App;

/// <summary>The application.</summary>
public partial class App : Application
{
    private Composition? _composition;

    /// <inheritdoc />
    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    /// <inheritdoc />
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            _composition = Composition.Create();
            desktop.MainWindow = new MainWindow(_composition);

            // Disposing tears down the keyboard hook and releases the audio device. Leaving
            // a low-level hook installed after exit is the kind of thing that makes a
            // machine feel broken until it is rebooted.
            desktop.ShutdownRequested += (_, _) =>
            {
                _composition?.DisposeAsync().AsTask().GetAwaiter().GetResult();
                _composition = null;
            };
        }

        base.OnFrameworkInitializationCompleted();
    }
}
