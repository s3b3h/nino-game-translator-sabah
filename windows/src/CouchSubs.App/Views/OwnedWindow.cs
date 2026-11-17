// SPDX-License-Identifier: AGPL-3.0-only

using System.Linq;
using System.Windows;

namespace CouchSubs.App.Views;

/// <summary>
/// Ayarlar, Geçmiş ve Hakkında: sahibinin üstünde duran ama onu kilitlemeyen tek pencere (#223). Aynı pencere zaten
/// açıksa yenisi açılmaz, var olan öne getirilir. Sahibi kapanınca bu pencere de kapanır.
/// </summary>
internal static class OwnedWindow
{
    public static void Show<T>(Window? owner, Func<T> create) where T : Window
    {
        var open = Application.Current?.Windows.OfType<T>().FirstOrDefault(window => window.IsVisible);
        if (open is not null)
        {
            if (open.WindowState == WindowState.Minimized) open.WindowState = WindowState.Normal;
            open.Activate();
            return;
        }
        var window = create();
        window.Owner = owner;
        window.Show();
    }
}
