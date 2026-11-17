// SPDX-License-Identifier: AGPL-3.0-only

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using CouchSubs.App.Theme;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.App.Views.Steps;

public partial class WelcomeStep : UserControl
{
    public WelcomeStep()
    {
        InitializeComponent();
        // Arapça arayüzde de bayraklar sağ üstte kalır (sağdan sola düzende "Left" görünürde sağdır).
        if (RightToLeft.Interface) Flags.HorizontalAlignment = HorizontalAlignment.Left;
        DataContextChanged += (_, e) =>
        {
            if (e.OldValue is AppController old) old.PropertyChanged -= OnControllerChanged;
            if (e.NewValue is AppController controller) controller.PropertyChanged += OnControllerChanged;
            ShowFlags();
        };
        Unloaded += (_, _) =>
        {
            if (DataContext is AppController controller) controller.PropertyChanged -= OnControllerChanged;
        };
        Loaded += (_, _) =>
        {
            if (Controller is not { } controller) return;
            Ps5.IsChecked = !controller.IsXbox;
            Xbox.IsChecked = controller.IsXbox;
            Ps5.IsEnabled = Xbox.IsEnabled = !controller.ConsoleKindLocked;
            ShowRequirements();
        };
    }

    /// <summary>Konsol seçimi (CouchSubs): Xbox seçilirse PS5 eşleştirmesi yerine Microsoft hesabıyla Xbox'a bağlanılır.</summary>
    private void OnSelected(object sender, RoutedEventArgs e)
    {
        if (!IsLoaded || Controller is not { } controller) return;
        controller.SelectConsoleKind(Xbox.IsChecked == true ? GameConsoleKind.Xbox : GameConsoleKind.PlayStation);
        ShowRequirements();
    }

    private void ShowRequirements()
    {
        if (Controller is not { } controller) return;
        var text = Localizer.Current;
        Layout.Message = controller.IsXbox
            ? text["Xbox support is in beta. Nino reads the subtitles in the game picture and shows the translation on your TV or computer. You keep playing with your own controller."]
            : text["Nino reads the English subtitles of your PS5 or Xbox games and shows a Turkish translation on your TV, on top of the game. You keep playing on the TV with your own controller."];
        XboxRequirements.Visibility = controller.IsXbox ? Visibility.Visible : Visibility.Collapsed;
        Ps5Requirements.Visibility = controller.IsXbox ? Visibility.Collapsed : Visibility.Visible;
    }

    private AppController? Controller => DataContext as AppController;

    /// <summary>Nino: oyunu bu bilgisayarda Remote Play ile oynayanlar PS5 ve TV adımlarını atlar.</summary>
    private void OnGameWindow(object sender, RoutedEventArgs e) => Controller?.UseGameWindowSetup();

    private void OnXbox(object sender, RoutedEventArgs e) => Controller?.UseXboxWindowSetup();

    /// <summary>Nino: Capture Card olanlar ikinci hesap ve PS5 eşleştirmesi yerine kart rehberine geçer.</summary>
    private void OnCaptureCard(object sender, RoutedEventArgs e) => Controller?.UseCaptureCardSetup();

    private void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppController.Settings)) ShowFlags();
    }

    /// <summary>
    /// Nino: çeviri dili sağ üstte bayraklı açılır listeyle seçilir (seçili dilin bayrağı ve adı; Türkçe en üstte).
    /// 11 bayrağı yan yana dizmek kalabalık olurdu.
    /// </summary>
    private void ShowFlags()
    {
        Flags.Children.Clear();
        if (Controller is not { } controller) return;
        var picker = new ComboBox { MinWidth = 190, FlowDirection = FlowDirection.LeftToRight };
        AutomationPropertiesHelper.SetName(picker, Localizer.Current["Translation language"]);
        foreach (var (code, name) in TargetLanguage.Choices)
            picker.Items.Add(new ComboBoxItem { Content = Views.LanguageFlags.Row(code, name), Tag = code,
                                                IsSelected = TargetLanguage.Code(controller.Settings.TargetLanguage) == code });
        picker.SelectionChanged += (_, _) =>
        {
            if (picker.SelectedItem is ComboBoxItem { Tag: string code } && code != controller.Settings.TargetLanguage)
                controller.Settings = controller.Settings with { TargetLanguage = code };
        };
        Flags.Children.Add(picker);
    }
}

/// <summary>Ekran okuyucu adı (AutomationProperties.Name).</summary>
internal static class AutomationPropertiesHelper
{
    public static void SetName(DependencyObject element, string name) =>
        System.Windows.Automation.AutomationProperties.SetName(element, name);
}
