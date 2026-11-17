// SPDX-License-Identifier: AGPL-3.0-only

using System.Diagnostics;
using System.Reflection;
using System.Windows;
using System.Windows.Navigation;
using CouchSubs.Shell;

namespace CouchSubs.App.Views;

public partial class AboutWindow : Window
{
    internal AboutWindow()
    {
        InitializeComponent();
        // Derleme sürümü (AssemblyVersion) ön sürüm ekini taşımaz: 0.1.0-beta.38 "0.1.0" görünüyordu. Etiketteki sürüm
        // InformationalVersion'dadır; güncelleme denetimi de onu kullanır.
        Version.Text = AppVersion.Current(Assembly.GetEntryAssembly() ?? typeof(AboutWindow).Assembly);
    }

    public static void Open(Window? owner) => OwnedWindow.Show(owner, () => new AboutWindow());

    private void OnLink(object sender, RequestNavigateEventArgs e) =>
        Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true });

    private void OnClose(object sender, RoutedEventArgs e) => Close();
}
