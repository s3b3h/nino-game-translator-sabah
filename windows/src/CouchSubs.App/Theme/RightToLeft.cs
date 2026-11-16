// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Controls;
using CouchSubs.Core;

namespace CouchSubs.App.Theme;

/// <summary>
/// Nino: Arapça. Arayüz Arapçaysa pencereler sağdan sola açılır (bkz. <see cref="ApplyInterfaceDirection"/>); PS5 görüntüsü,
/// çerçeve, sürüklenen düğme ve sahne gibi aynalanmaması gerekenler <see cref="KeepLeftToRight"/> ile soldan sağa kalır.
/// Altyazının yönü yazının kendisinden seçilir: Arap harfi varsa sağdan sola (konuşmacı adıyla başlasa da).
/// </summary>
public static class RightToLeft
{
    /// <summary>Arayüz dili sağdan sola mı (Arapça).</summary>
    public static bool Interface => Localizer.Current.IsRightToLeft;

    /// <summary>Uygulama açılırken, ilk pencereden önce bir kez çağrılır: bütün pencereler arayüzün yönüyle açılır.</summary>
    public static void ApplyInterfaceDirection()
    {
        if (!Interface) return;
        try
        {
            FrameworkElement.FlowDirectionProperty.OverrideMetadata(typeof(Window),
                new FrameworkPropertyMetadata(FlowDirection.RightToLeft, FrameworkPropertyMetadataOptions.Inherits | FrameworkPropertyMetadataOptions.AffectsParentArrange));
        }
        catch (ArgumentException)
        {
            // Üst veri zaten verilmişse pencereler açılırken tek tek sağdan sola yapılır.
            EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent, new RoutedEventHandler((sender, _) =>
            {
                if (sender is Window window && window.ReadLocalValue(FrameworkElement.FlowDirectionProperty) == DependencyProperty.UnsetValue)
                    window.FlowDirection = FlowDirection.RightToLeft;
            }));
        }
    }

    public static void KeepLeftToRight(FrameworkElement element) => element.FlowDirection = FlowDirection.LeftToRight;

    /// <summary>Altyazı satırını yazar: Arapçaysa sağdan sola işaretli ve sağdan sola akışlı.</summary>
    public static void SetSubtitle(TextBlock block, string text)
    {
        var arabic = TargetLanguage.ContainsArabic(text);
        block.Text = TargetLanguage.DisplayText(text);
        block.FlowDirection = arabic ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;
    }
}
