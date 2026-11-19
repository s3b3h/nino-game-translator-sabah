// SPDX-License-Identifier: AGPL-3.0-only
// Nino: "Nino'ya Sor" kurulum yardımcısı. Ana ekranın ve sihirbazın sağ altındaki robot düğmesiyle ya da Ayarlar ›
// Hakkında › Nino'ya Sor ile açılır. Kodla kurulur (Sorun Bildir penceresi gibi).

using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using CouchSubs.App.Controls;
using CouchSubs.App.Services;
using CouchSubs.Core;
using CouchSubs.Shell;
using Image = System.Windows.Controls.Image;
using Glyphs = CouchSubs.App.Controls.Glyphs;
using Path = System.IO.Path;
using TextBox = System.Windows.Controls.TextBox;

namespace CouchSubs.App.Views;

/// <summary>
/// Sohbet penceresi: üstte göz kırpan robot, "Nino" ve "Kurulum yardımcısı", sağda Yeni sohbet; ortada mesajlar (Nino
/// solda, kullanıcı sağda mavi); altta ekran görüntüleri, yazı kutusu, ekle ve gönder düğmeleri. Sohbet
/// <see cref="NinoChat.Session"/>'dadır: pencere kapanıp açılınca kalır, uygulama kapanınca silinir. İstek
/// <see cref="NinoAssistant"/>'ta kurulur; kuruluş kimliği, fotoğraf küçültme ve sunucu adresi Sorun Bildir'le aynıdır.
/// </summary>
public sealed class AskNinoWindow : Window
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(60) };
    private static string T(string key) => Localizer.Current[key];
    private const double Thumb = 56;

    private static readonly string Greeting =
        "Hi! I'm Nino 👋 You can ask me anything about setting up. First, tell me: which devices do you have? (PS5 or Xbox, TV or monitor, phone or computer) Where do you want to set it up?";
    private static readonly string[] Suggestions = ["PS5 + TV + phone", "PS5 + monitor + computer", "Xbox + TV", "How do I install the TV app?"];

    /// <summary>Gösterilen küçük resimler: aynı JPEG her yenilemede yeniden çözülmesin.</summary>
    private static readonly ConditionalWeakTable<byte[], BitmapSource> Thumbnails = new();

    private readonly AppController controller;
    private readonly NinoChat chat = NinoChat.Session;
    private readonly List<(BitmapSource Picture, byte[] Jpeg)> attachments = [];
    private readonly List<FrameworkElement> bubbles = [];
    private readonly StackPanel messages = new() { Margin = new Thickness(16, 16, 16, 8) };
    private readonly ScrollViewer scroller = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = false };
    private readonly NinoBot headerBot = new() { Width = 44, Height = 44 };
    private readonly TextBox input = new()
    {
        AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MaxLength = NinoAssistant.MaxText, MaxHeight = 132,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(14, 9, 14, 9),
    };
    private readonly Button attach = new();
    private readonly Button send = new();
    private readonly WrapPanel attachmentRow = new() { Margin = new Thickness(0, 0, 0, 4) };
    private readonly TextBlock composerError = new() { TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed, Margin = new Thickness(0, 0, 0, 8) };

    private AskNinoWindow(AppController controller)
    {
        this.controller = controller;
        Title = T("Ask Nino");
        Width = 440;
        Height = 680;
        MinWidth = 360;
        MinHeight = 460;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        AllowDrop = true;
        SetResourceReference(BackgroundProperty, "windowBackgroundBrush");
        SetResourceReference(ForegroundProperty, "textPrimaryBrush");

        scroller.Content = messages;
        var header = Header();
        var composer = Composer();
        DockPanel.SetDock(header, Dock.Top);
        DockPanel.SetDock(composer, Dock.Bottom);
        Content = new DockPanel { LastChildFill = true, Children = { header, composer, scroller } };

        chat.Changed += OnChatChanged;
        Closed += (_, _) => chat.Changed -= OnChatChanged;
        SizeChanged += (_, _) => FitBubbles();

        // Sürükle-bırak ve Ctrl+V: Sorun Bildir'deki gibi (metin kutusu dosyayı kendisi almasın diye önizleme olaylarında).
        PreviewDragOver += OnDragOver;
        PreviewDragEnter += OnDragOver;
        PreviewDrop += OnDrop;
        InputBindings.Add(new KeyBinding(ApplicationCommands.Paste, Key.V, ModifierKeys.Control));
        CommandManager.AddPreviewCanExecuteHandler(this, OnCanPaste);
        CommandManager.AddPreviewExecutedHandler(this, OnPaste);
        Loaded += (_, _) => { Render(); input.Focus(); };
    }

    /// <summary>
    /// Pencereyi açar (açıksa öne getirir). Sahibi her zaman ana penceredir: Ayarlar'dan açılsa da Ayarlar kapanınca
    /// sohbet kapanmasın.
    /// </summary>
    public static void Open(AppController controller)
    {
        var owner = Application.Current?.Windows.OfType<ShellWindow>().FirstOrDefault() ?? Application.Current?.MainWindow;
        OwnedWindow.Show(owner, () => new AskNinoWindow(controller));
    }

    private static void Named(DependencyObject element, string name) => AutomationProperties.SetName(element, name);

    // --- Düzen ---

    private Border Header()
    {
        var title = new TextBlock { Text = "Nino" };
        title.SetResourceReference(StyleProperty, "HeadlineText");
        var subtitle = new TextBlock { Text = T("Setup helper") };
        subtitle.SetResourceReference(StyleProperty, "CaptionText");
        var names = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0), Children = { title, subtitle } };

        var newChat = new Button { Padding = new Thickness(12, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center, ToolTip = T("New chat") };
        newChat.SetResourceReference(StyleProperty, "GhostButton");
        var plus = new TextBlock { Text = Glyphs.Add, FontSize = 14, Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
        plus.SetResourceReference(StyleProperty, "GlyphText");
        plus.SetResourceReference(TextBlock.ForegroundProperty, "accentTextBrush");
        newChat.Content = new StackPanel { Orientation = Orientation.Horizontal, Children = { plus, new TextBlock { Text = T("New chat"), VerticalAlignment = VerticalAlignment.Center } } };
        Named(newChat, T("New chat"));
        newChat.Click += (_, _) => { chat.Reset(); ClearAttachments(); input.Clear(); input.Focus(); };

        var row = new DockPanel();
        DockPanel.SetDock(newChat, Dock.Right);
        row.Children.Add(newChat);
        row.Children.Add(new StackPanel { Orientation = Orientation.Horizontal, Children = { headerBot, names } });
        var header = new Border { Padding = new Thickness(16, 12, 12, 12), BorderThickness = new Thickness(0, 0, 0, 1), Child = row };
        header.SetResourceReference(Border.BorderBrushProperty, "borderBrush");
        return header;
    }

    private Border Composer()
    {
        attach.SetResourceReference(StyleProperty, "IconButton");
        attach.Content = Glyph(Glyphs.Attach, 16);
        attach.ToolTip = T("Up to 3 screenshots per message. You can also drag them here or paste with Ctrl+V.");
        attach.VerticalAlignment = VerticalAlignment.Bottom;
        Named(attach, T("Attach screenshot"));
        attach.Click += (_, _) => PickPictures();

        send.SetResourceReference(StyleProperty, "PrimaryButton");
        send.Width = 40;
        send.Height = 40;
        send.Padding = new Thickness(0);
        send.VerticalAlignment = VerticalAlignment.Bottom;
        var arrow = Glyph(Glyphs.Send, 16);
        arrow.SetResourceReference(TextBlock.ForegroundProperty, "onAccentBrush");
        // Arapça arayüzde ok sola baksın (yazı simgeleri kendiliğinden aynalanmaz).
        if (Theme.RightToLeft.Interface) { arrow.RenderTransformOrigin = new Point(0.5, 0.5); arrow.RenderTransform = new ScaleTransform(-1, 1); }
        send.Content = arrow;
        send.ToolTip = T("Send");
        Named(send, T("Send"));
        send.Click += async (_, _) => await SendAsync();

        Named(input, T("Ask Nino…"));
        input.TextChanged += (_, _) => UpdateSend();
        // Enter gönderir, Shift+Enter yeni satır açar.
        input.PreviewKeyDown += async (_, e) =>
        {
            if (e.Key != Key.Enter || Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) return;
            e.Handled = true;
            await SendAsync();
        };
        var field = ReportProblemWindow.WithPlaceholder(input, T("Ask Nino…"));
        field.Margin = new Thickness(8, 0, 8, 0);

        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(field, 1);
        Grid.SetColumn(send, 2);
        row.Children.Add(attach);
        row.Children.Add(field);
        row.Children.Add(send);

        composerError.SetResourceReference(StyleProperty, "ErrorText");
        var note = new TextBlock
        {
            Text = T("Nino's answers are written by AI and may be wrong. Your messages and screenshots go to Nino's server. Don't send passwords."),
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0), TextAlignment = TextAlignment.Center,
        };
        note.SetResourceReference(StyleProperty, "CaptionText");

        var composer = new Border
        {
            Padding = new Thickness(12, 10, 12, 10), BorderThickness = new Thickness(0, 1, 0, 0),
            Child = new StackPanel { Children = { attachmentRow, composerError, row, note } },
        };
        composer.SetResourceReference(Border.BorderBrushProperty, "borderBrush");
        ShowAttachments();
        UpdateSend();
        return composer;
    }

    private static TextBlock Glyph(string glyph, double size)
    {
        var block = new TextBlock { Text = glyph, FontSize = size, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        block.SetResourceReference(StyleProperty, "GlyphText");
        return block;
    }

    private void UpdateSend()
    {
        send.IsEnabled = !chat.Waiting && NinoAssistant.CanSend(input.Text, attachments.Count);
        attach.IsEnabled = attachments.Count < NinoAssistant.MaxImagesPerMessage;
    }

    // --- Mesajlar ---

    private void OnChatChanged()
    {
        if (!Dispatcher.CheckAccess()) { Dispatcher.BeginInvoke(OnChatChanged); return; }
        Render();
    }

    /// <summary>Bütün sohbeti yeniden çizer (en çok birkaç düzine baloncuk) ve en alta kayar.</summary>
    private void Render()
    {
        messages.Children.Clear();
        bubbles.Clear();
        headerBot.Thinking = chat.Waiting;

        messages.Children.Add(NinoRow(Paragraphs(T(Greeting))));
        if (chat.IsEmpty && !chat.Waiting) messages.Children.Add(SuggestionChips());

        for (var i = 0; i < chat.Entries.Count; i++)
        {
            var entry = chat.Entries[i];
            var last = i == chat.Entries.Count - 1;
            switch (entry.Kind)
            {
                case NinoChat.EntryKind.User: messages.Children.Add(UserRow(entry)); break;
                case NinoChat.EntryKind.Nino:
                    var reply = NinoRow(Paragraphs(entry.Text), entry.Report is null ? null : ReportChip());
                    messages.Children.Add(reply);
                    if (last) Announce(reply, "Nino: " + entry.Text);
                    break;
                default:
                    var notice = NinoRow(Notice(entry, last, out var noticeText));
                    messages.Children.Add(notice);
                    if (last) Announce(notice, "Nino: " + noticeText);
                    break;
            }
        }
        if (chat.Waiting) messages.Children.Add(TypingRow());
        FitBubbles();
        UpdateSend();
        Dispatcher.BeginInvoke(scroller.ScrollToEnd, System.Windows.Threading.DispatcherPriority.Background);
    }

    /// <summary>
    /// Yeni cevap ekran okuyucuya okunur. Panellerin otomasyon eşi yoktur; bu yüzden canlı bölge baloncuktaki ilk yazıdır
    /// (TextBlock), adı da cevabın tamamı.
    /// </summary>
    private static void Announce(FrameworkElement row, string text)
    {
        if (LogicalTreeHelper.GetChildren(row).OfType<object>().SelectMany(Descendants).OfType<TextBlock>().FirstOrDefault() is not { } block) return;
        AutomationProperties.SetName(block, text);
        AutomationProperties.SetLiveSetting(block, AutomationLiveSetting.Polite);
        block.Loaded += (_, _) =>
            (UIElementAutomationPeer.FromElement(block) ?? UIElementAutomationPeer.CreatePeerForElement(block))?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
    }

    private static IEnumerable<object> Descendants(object node) =>
        node is DependencyObject parent ? [node, .. LogicalTreeHelper.GetChildren(parent).OfType<object>().SelectMany(Descendants)] : [node];

    /// <summary>Baloncuklar pencerenin ~%78'ini geçmez.</summary>
    private void FitBubbles()
    {
        var max = Math.Max(220, (scroller.ActualWidth > 0 ? scroller.ActualWidth : Width) * 0.78 - 40);
        foreach (var bubble in bubbles) bubble.MaxWidth = max;
    }

    private Border Bubble(UIElement content, bool user)
    {
        var bubble = new Border
        {
            Padding = new Thickness(14, 10, 14, 10),
            // Konuşma kuyruğu tarafındaki alt köşe daha az yuvarlak.
            CornerRadius = user ? new CornerRadius(18, 18, 6, 18) : new CornerRadius(18, 18, 18, 6),
            HorizontalAlignment = user ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            Child = content,
        };
        bubble.SetResourceReference(Border.BackgroundProperty, user ? "accentBrush" : "surface2Brush");
        bubble.SetResourceReference(TextElement.ForegroundProperty, user ? "onAccentBrush" : "textPrimaryBrush");
        bubbles.Add(bubble);
        return bubble;
    }

    /// <summary>Nino satırı: altta küçük robot, yanında açık renkli baloncuk; isteğe bağlı baloncuk altı (bildirim rozeti).</summary>
    private FrameworkElement NinoRow(UIElement content, UIElement? below = null, bool thinking = false)
    {
        var avatar = new NinoBot { Width = 28, Height = 28, Blinks = false, Thinking = thinking, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 8, 2) };
        var column = new StackPanel { Children = { Bubble(content, user: false) } };
        if (below is not null) column.Children.Add(below);
        var row = new DockPanel { Margin = new Thickness(0, 0, 0, 12), HorizontalAlignment = HorizontalAlignment.Left };
        row.Children.Add(avatar);
        row.Children.Add(column);
        return row;
    }

    private FrameworkElement UserRow(NinoChat.Entry entry)
    {
        var content = new StackPanel();
        if (entry.Jpegs.Count > 0)
        {
            var pictures = new WrapPanel { Margin = new Thickness(0, 0, 0, entry.Text.Length > 0 ? 8 : 0) };
            foreach (var jpeg in entry.Jpegs) pictures.Children.Add(Rounded(Decode(jpeg), 96, new Thickness(0, 0, 6, 6)));
            content.Children.Add(pictures);
        }
        if (entry.Text.Length > 0) content.Children.Add(new TextBlock { Text = entry.Text, TextWrapping = TextWrapping.Wrap });
        var bubble = Bubble(content, user: true);
        bubble.Margin = new Thickness(48, 0, 0, 12);
        return bubble;
    }

    /// <summary>Adım rozetinin çapı; maddenin noktası da aynı genişlikte durur ki yazılar aynı hizaya gelsin.</summary>
    private const double BadgeSize = 21;

    /// <summary>
    /// Nino'nun metni: paragraflar, mavi yuvarlak rozetli numaralı adımlar ve noktalı maddeler (asılı girinti: kayan
    /// satırlar rozetin altına değil yazının hizasına gelir), tıklanabilir http(s) bağlantıları. Bloklara ayırma
    /// NinoAssistant.Format'ta (Mac, iPhone ve Android'le aynı kurallar). Sağdan sola dillerde pencerenin FlowDirection'ı
    /// miras kalır; Grid sütunları kendiliğinden aynalanır, rozet sağa geçer.
    /// </summary>
    private static StackPanel Paragraphs(string text)
    {
        var panel = new StackPanel();
        var blocks = NinoAssistant.Format(text);
        for (var i = 0; i < blocks.Count; i++)
        {
            var block = blocks[i];
            var body = new TextBlock { TextWrapping = TextWrapping.Wrap };
            foreach (var span in block.Spans)
            {
                if (span.Link is not { } uri) { body.Inlines.Add(new Run(span.Text)); continue; }
                var link = new Hyperlink(new Run(span.Text)) { NavigateUri = uri, ToolTip = uri.ToString() };
                link.SetResourceReference(TextElement.ForegroundProperty, "accentTextBrush");
                link.RequestNavigate += (_, e) => { BrowserLauncher.Open(e.Uri); e.Handled = true; };
                body.Inlines.Add(link);
            }
            var gap = new Thickness(0, i == 0 ? 0 : block.IsListItem && blocks[i - 1].IsListItem ? 8 : 10, 0, 0);
            if (!block.IsListItem)
            {
                body.Margin = gap;
                panel.Children.Add(body);
                continue;
            }
            // Satır yüksekliği ~19 px, rozet 21 px: ilk satırın ortası rozetin ortasına gelsin diye yazı biraz aşağıda.
            body.Margin = new Thickness(0, 1, 0, 0);
            Grid.SetColumn(body, 1);
            var item = new Grid { Margin = gap };
            item.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            item.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            // Yazı önce eklenir: ekran okuyucunun canlı bölgesi (Announce) rozetteki numara değil, ilk yazı olsun.
            item.Children.Add(body);
            var marker = block.Kind == NinoAssistant.BlockKind.Step ? StepBadge(block.Number ?? "") : BulletDot();
            Grid.SetColumn(marker, 0);
            item.Children.Add(marker);
            panel.Children.Add(item);
        }
        return panel;
    }

    /// <summary>Numaralı adımın rozeti: vurgu mavisi daire, beyaz kalın numara.</summary>
    private static Border StepBadge(string number)
    {
        var label = new TextBlock
        {
            Text = number,
            FontSize = 11.5,
            FontWeight = FontWeights.Bold,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        label.SetResourceReference(TextBlock.ForegroundProperty, "onAccentBrush");
        AutomationProperties.SetName(label, number + ".");
        var badge = new Border
        {
            MinWidth = BadgeSize,
            Height = BadgeSize,
            CornerRadius = new CornerRadius(BadgeSize / 2),
            Padding = new Thickness(number.Length > 1 ? 4 : 0, 0, number.Length > 1 ? 4 : 0, 0),
            Margin = new Thickness(0, 0, 8, 0),
            VerticalAlignment = VerticalAlignment.Top,
            Child = label,
        };
        badge.SetResourceReference(Border.BackgroundProperty, "accentBrush");
        return badge;
    }

    /// <summary>Maddenin noktası: rozet genişliğinde bir sütunda, ilk satırın ortasında küçük mavi daire.</summary>
    private static Border BulletDot()
    {
        var dot = new Ellipse { Width = 6, Height = 6, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        dot.SetResourceReference(Shape.FillProperty, "accentBrush");
        return new Border { Width = BadgeSize, Height = BadgeSize, Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Top, Child = dot };
    }

    private WrapPanel SuggestionChips()
    {
        var chips = new WrapPanel { Margin = new Thickness(36, 0, 0, 12) };
        foreach (var key in Suggestions)
        {
            var text = T(key);
            var chip = new Button
            {
                Content = text, MinHeight = 34, Padding = new Thickness(14, 0, 14, 0), Margin = new Thickness(0, 0, 8, 8),
            };
            chip.SetResourceReference(StyleProperty, "SecondaryButton");
            chip.SetResourceReference(ForegroundProperty, "accentTextBrush");
            Named(chip, text);
            chip.Click += async (_, _) => await SendAsync(text);
            chips.Children.Add(chip);
        }
        return chips;
    }

    private static Border ReportChip()
    {
        var label = new TextBlock { Text = T("Report sent ✓"), FontSize = 12, FontWeight = FontWeights.SemiBold };
        label.SetResourceReference(TextBlock.ForegroundProperty, "successBrush");
        var chip = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(0, 6, 0, 0), HorizontalAlignment = HorizontalAlignment.Left, Child = label };
        chip.SetResourceReference(Border.BackgroundProperty, "successSoftBrush");
        return chip;
    }

    /// <summary>Yerel uyarı baloncuğu (sunucuya gitmez): hazır değil, sınır, yoğunluk, bağlantı.</summary>
    private StackPanel Notice(NinoChat.Entry entry, bool last, out string text)
    {
        text = entry.Outcome switch
        {
            NinoAssistant.Outcome.Disabled => T("I'm almost ready! Until then, send your question with Report a Problem and the team will answer."),
            NinoAssistant.Outcome.RateLimited => T("You've asked a lot today 🙂 Let's continue tomorrow."),
            NinoAssistant.Outcome.Busy => T("I'm very busy right now, try again in a bit."),
            NinoAssistant.Outcome.Rejected => T("I couldn't read that message. Try writing it a bit shorter or with fewer screenshots."),
            _ => T("I couldn't reach the server. Check your internet and try again."),
        };
        var panel = new StackPanel { Children = { new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap } } };
        Button? action = null;
        if (entry.Outcome == NinoAssistant.Outcome.Disabled)
        {
            action = new Button { Content = T("Report a Problem") };
            action.SetResourceReference(StyleProperty, "PrimaryButton");
            action.Click += (_, _) => ReportProblemWindow.Open(this, controller);
        }
        else if (entry.CanRetry && last && !chat.Waiting)
        {
            action = new Button { Content = T("Try again") };
            action.SetResourceReference(StyleProperty, "SecondaryButton");
            action.Click += async (_, _) => await chat.RetryAsync(Ask);
        }
        if (action is not null)
        {
            action.MinHeight = 34;
            action.Padding = new Thickness(16, 0, 16, 0);
            action.Margin = new Thickness(0, 10, 0, 0);
            panel.Children.Add(action);
        }
        return panel;
    }

    /// <summary>Yazıyor: üç nokta sırayla parlar, robot hafifçe sallanır.</summary>
    private FrameworkElement TypingRow()
    {
        var dots = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(2, 5, 2, 5) };
        for (var i = 0; i < 3; i++)
        {
            var dot = new Ellipse { Width = 7, Height = 7, Margin = new Thickness(i == 0 ? 0 : 5, 0, 0, 0), Opacity = 0.35 };
            dot.SetResourceReference(Shape.FillProperty, "textSecondaryBrush");
            if (!NinoBot.ReduceMotion)
            {
                dot.BeginAnimation(OpacityProperty, new DoubleAnimation(0.25, 1, TimeSpan.FromMilliseconds(420))
                {
                    AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, BeginTime = TimeSpan.FromMilliseconds(i * 160),
                });
            }
            dots.Children.Add(dot);
        }
        // Ekran okuyucu için: noktaların yanında görünmez "Nino yazıyor…" yazısı.
        dots.Children.Add(new TextBlock { Text = T("Nino is typing…"), Width = 1, Opacity = 0, IsHitTestVisible = false });
        var row = NinoRow(dots, thinking: true);
        Announce(row, T("Nino is typing…"));
        return row;
    }

    private static BitmapSource Decode(byte[] jpeg)
    {
        if (Thumbnails.TryGetValue(jpeg, out var cached)) return cached;
        var image = new BitmapImage();
        image.BeginInit();
        image.StreamSource = new MemoryStream(jpeg);
        image.DecodePixelWidth = 192;
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.EndInit();
        image.Freeze();
        Thumbnails.AddOrUpdate(jpeg, image);
        return image;
    }

    private static Border Rounded(BitmapSource picture, double size, Thickness margin)
    {
        var image = new Image { Source = picture, Stretch = Stretch.UniformToFill, Width = size, Height = size };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
        return new Border
        {
            Width = size, Height = size, Margin = margin, ClipToBounds = true, Child = image,
            Clip = new RectangleGeometry(new Rect(0, 0, size, size), 10, 10),
        };
    }

    // --- Gönderim ---

    private async Task SendAsync(string? suggestion = null)
    {
        if (chat.Waiting) return;
        var text = suggestion ?? input.Text;
        var jpegs = suggestion is null ? attachments.Select(item => item.Jpeg).ToList() : [];
        if (!NinoAssistant.CanSend(text, jpegs.Count)) return;
        if (suggestion is null)
        {
            input.Clear();
            ClearAttachments();
        }
        HideComposerError();
        await chat.SendAsync(text, jpegs, Ask);
    }

    /// <summary>Sohbeti sunucuya gönderir (arka planda); sunucu adresi yoksa bağlantı hatası sayılır.</summary>
    private Task<NinoAssistant.Result> Ask(IReadOnlyList<NinoAssistant.Turn> turns)
    {
        var endpoint = NinoAssistant.Endpoint(NinoPool.ConfiguredEndpoint(Path.Combine(AppPaths.Data, "pool")));
        var app = AppVersion.Current(Assembly.GetEntryAssembly() ?? typeof(AskNinoWindow).Assembly);
        var language = Localizer.Current.Language;
        var poolInstall = controller.PoolInstallId;
        // Cihaz bilgileri her mesajda yeniden alınır (TV sonradan bağlanmış olabilir); Nino bildirim açarsa ona eklenir.
        var device = controller.DeviceSummary(app);
        return Task.Run(async () =>
        {
            var install = ProblemReport.InstallId(poolInstall, Path.Combine(AppPaths.Data, "report-install.txt"));
            var payload = NinoAssistant.Build(install, app, language, turns, device: device);
            return await NinoAssistant.SendAsync(Http, endpoint, payload);
        });
    }

    // --- Ekran görüntüleri ---

    private void ShowAttachments()
    {
        attachmentRow.Children.Clear();
        foreach (var item in attachments)
        {
            var remove = new Button
            {
                Content = "✕", Width = 22, Height = 22, MinHeight = 0, Padding = new Thickness(0), FontSize = 10,
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 3, 3, 0),
                ToolTip = T("Remove photo"),
            };
            remove.SetResourceReference(StyleProperty, "SecondaryButton");
            Named(remove, T("Remove photo"));
            var current = item;
            remove.Click += (_, _) => { attachments.Remove(current); ShowAttachments(); UpdateSend(); };
            attachmentRow.Children.Add(new Grid { Margin = new Thickness(0, 0, 8, 6), Children = { Rounded(item.Picture, Thumb, new Thickness(0)), remove } });
        }
        attachmentRow.Visibility = attachments.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ClearAttachments()
    {
        attachments.Clear();
        ShowAttachments();
        UpdateSend();
    }

    private void PickPictures()
    {
        var picker = new Microsoft.Win32.OpenFileDialog
        {
            Title = T("Attach screenshot"),
            Multiselect = true,
            Filter = $"{T("Images")}|{ReportImages.PickerPattern}",
        };
        if (picker.ShowDialog(this) == true) _ = AddAsync(picker.FileNames.Select(path => (Func<BitmapSource?>)(() => ReportImages.Load(path))));
    }

    /// <summary>Görüntüleri sırayla açar, JPEG'e çevirir (arka planda, fotoğraf başına en çok 600 KB) ve ekler; en çok 3.</summary>
    private async Task AddAsync(IEnumerable<Func<BitmapSource?>> sources)
    {
        HideComposerError();
        var failed = false;
        foreach (var open in sources)
        {
            if (attachments.Count >= NinoAssistant.MaxImagesPerMessage) break;
            try
            {
                if (open() is not { } picture) continue;
                var jpeg = await Task.Run(() => ReportImages.Jpeg(picture, NinoAssistant.TargetImageBytes));
                if (jpeg is null) { failed = true; continue; }
                if (attachments.Count >= NinoAssistant.MaxImagesPerMessage) break;
                attachments.Add((picture, jpeg));
                ShowAttachments();
                UpdateSend();
            }
            catch (Exception exception) when (exception is NotSupportedException or FileFormatException or IOException
                                              or UnauthorizedAccessException or ArgumentException or InvalidOperationException or COMException)
            {
                failed = true;
            }
        }
        if (failed) ShowComposerError(T("This image could not be opened."));
    }

    private void ShowComposerError(string text)
    {
        composerError.Text = text;
        composerError.Visibility = Visibility.Visible;
    }

    private void HideComposerError() => composerError.Visibility = Visibility.Collapsed;

    private void OnDragOver(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop)) return;
        e.Effects = attachments.Count < NinoAssistant.MaxImagesPerMessage ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is not string[] files) return;
        e.Handled = true;
        _ = AddAsync(files.Where(ReportImages.IsImageFile).Select(path => (Func<BitmapSource?>)(() => ReportImages.Load(path))));
    }

    private void OnCanPaste(object sender, CanExecuteRoutedEventArgs e)
    {
        if (e.Command != ApplicationCommands.Paste || !ReportImages.PastesPicture()) return;
        e.CanExecute = attachments.Count < NinoAssistant.MaxImagesPerMessage;
        e.Handled = true;
    }

    private void OnPaste(object sender, ExecutedRoutedEventArgs e)
    {
        if (e.Command != ApplicationCommands.Paste || !ReportImages.PastesPicture()) return;
        e.Handled = true;
        try { _ = AddAsync(ReportImages.FromClipboardSources()); }
        catch (COMException) { ShowComposerError(T("This image could not be opened.")); }
    }
}
