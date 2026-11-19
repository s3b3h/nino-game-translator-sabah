// SPDX-License-Identifier: AGPL-3.0-only
// Nino: salon sahnesinin ölçüleri ve fiş/kablo hesabı (Mac'teki LivingRoomScene.Layout, plugTurn ve cable ile aynı sayılar).
// Çizimden ayrı, saf hesap: Mac'te de çalışan testlerle sınanır (WPF yalnız Windows'ta çalışır).

namespace CouchSubs.Shell;

/// <summary>Sahne pikseli cinsinden nokta (görselin sol üstü 0,0; y aşağı doğru artar).</summary>
public readonly record struct ScenePoint(double X, double Y)
{
    public double DistanceTo(ScenePoint other) => Math.Sqrt((other.X - X) * (other.X - X) + (other.Y - Y) * (other.Y - Y));
}

/// <summary>Sahne pikseli cinsinden dikdörtgen.</summary>
public readonly record struct SceneRect(double X, double Y, double Width, double Height)
{
    public double MidX => X + Width / 2;
    public double Bottom => Y + Height;
}

/// <summary>
/// Kablonun çizilecek yolu: <see cref="Lead"/> noktaları düz çizgilerle birleşir (ilk nokta başlangıç), son noktadan
/// <see cref="End"/>'e iki denetim noktalı eğri gider.
/// </summary>
public sealed record CableShape(IReadOnlyList<ScenePoint> Lead, ScenePoint Control1, ScenePoint Control2, ScenePoint End);

/// <summary>
/// Salon sahnesi konsola göre değişir: PS5'li salon (living-room.png) ya da Xbox'lı salon (living-room-xbox.png; aynı
/// TV, sehpa ve priz). Koordinatlar görsellerin piksel ölçüsündedir (1672×941) ve Mac'tekilerle aynıdır.
/// </summary>
public sealed record LivingRoomLayout
{
    public const double CanvasWidth = 1672, CanvasHeight = 941;
    /// <summary>TV ekranının içi bu genişlikteki bir ekrana göre tasarlanır ve görseldeki ekrana büyütülür (Mac: 588 nokta).</summary>
    public const double LogicalScreenWidth = 588;
    /// <summary>Prize bu kadar yaklaşınca fiş tam prize dönmüş olur (sahne pikseli).</summary>
    public const double TurnDone = 120;
    /// <summary>Kablonun serbest boyu: fiş konsola yaklaşınca kablo bu boydan artanı kadar sarkar.</summary>
    public const double CableLength = 330;
    public const double CableWidth = 8;
    /// <summary>Görseldeki prizin kenar uzunluğu (sahne pikseli).</summary>
    public const double SocketSize = 86;

    public required string Image { get; init; }
    public required SceneRect Screen { get; init; }
    public required SceneRect TvFrame { get; init; }
    public required SceneRect StandFrame { get; init; }
    public required ScenePoint Socket { get; init; }
    /// <summary>Kablonun çizilmeye başladığı yer (PS5'te görseldeki kablonun ucu, Xbox'ta konsolun sağ arkası).</summary>
    public required ScenePoint CableStart { get; init; }
    /// <summary>
    /// Görseldeki kablonun (varsa) son parçası: çizilen kablo bunun üstünden başlar, ek yeri görünmez. Yoksa boş (Xbox
    /// görselinde kablo yok; kablo <see cref="CableStart"/>taki girişten küçük bir fiş başıyla çıkar).
    /// </summary>
    public IReadOnlyList<ScenePoint> CableLead { get; init; } = [];
    /// <summary>Kablonun çizilen parçasının başladığı yerdeki yönü: görseldeki kablonun bittiği eğimle sürer.</summary>
    public ScenePoint CableOut { get; init; } = new(1, 0.1);
    /// <summary>Fiş çıkıkken sehpanın yanından sarkar.</summary>
    public required ScenePoint Hanging { get; init; }

    /// <summary>Ekran içeriğinin büyütme oranı (Mac'teki 588 noktalık ekrandan görseldeki ekrana).</summary>
    public double ScreenScale => Screen.Width / LogicalScreenWidth;

    /// <summary>
    /// Sehpayı pencerenin ortasına getirmek için sahnenin soluna eklenen boşluk (görselde sağda priz ve konsol olduğu için
    /// sehpa biraz soldadır). Mac'teki kaydırmanın (genişlik/2 − sehpanın ortası) iki katı: ortalanan tuval o kadar kayar.
    /// </summary>
    public double Shift => Math.Max(0, 2 * (CanvasWidth / 2 - StandFrame.MidX));

    public static readonly LivingRoomLayout Ps5 = new()
    {
        Image = "living-room.png",
        Screen = new(149, 40, 1151, 595),
        TvFrame = new(139, 27, 1171, 621),
        StandFrame = new(49, 713, 1502, 160),
        Socket = new(1564, 378),
        CableStart = new(1550, 734),
        // Görseldeki kablo: PS5'in arkasından yatay çıkar (y≈706), 1523'ten sonra aşağı kıvrılıp (1552, 727)'de biter.
        // Çizilen kablo aynı yolu izleyip oradan devam eder.
        CableLead = [new(1490, 706), new(1522, 706), new(1535, 709), new(1545, 716), new(1552, 727)],
        CableOut = new(0.5, 0.87),
        Hanging = new(1600, 885),
    };

    public static readonly LivingRoomLayout Xbox = new()
    {
        Image = "living-room-xbox.png",
        Screen = new(136, 40, 1185, 596),
        TvFrame = new(121, 26, 1214, 630),
        StandFrame = new(43, 733, 1580, 167),
        Socket = new(1561, 381),
        CableStart = new(1572, 722),
        Hanging = new(1646, 912),
    };

    public static LivingRoomLayout For(bool xbox) => xbox ? Xbox : Ps5;

    /// <summary>
    /// Fiş çıkıkken uçlarının baktığı yön (radyan; 0 = aşağı, saat yönü artı). Dinlenirken yerçekimiyle aşağı sarkar;
    /// prize yaklaştıkça yumuşak geçişle prize döner, prize <see cref="TurnDone"/> kala tam dönüktür. Eskiden hep aşağı
    /// bakıyordu (prize götürülürken de).
    /// </summary>
    public static double PlugTurn(ScenePoint plug, ScenePoint socket, ScenePoint rest)
    {
        var restDistance = socket.DistanceTo(rest);
        var distance = socket.DistanceTo(plug);
        if (!(restDistance > TurnDone && distance > 1)) return 0;
        var t = Math.Clamp((restDistance - distance) / (restDistance - TurnDone), 0, 1);
        var eased = t * t * (3 - 2 * t);
        // Uçlar dönmeden önce (0, +1) yönüne bakar; θ kadar dönünce (−sin θ, cos θ). Prize bakması için:
        var toward = Math.Atan2(-(socket.X - plug.X), socket.Y - plug.Y);
        return eased * toward;
    }

    /// <summary>θ kadar dönmüş fişin uçlarının yönü (birim vektör).</summary>
    public static ScenePoint Prong(double turn) => new(-Math.Sin(turn), Math.Cos(turn));

    /// <summary>Fişin şu anki yönü (bu sahnenin prizine ve dinlenme yerine göre).</summary>
    public double PlugTurn(ScenePoint plug) => PlugTurn(plug, Socket, Hanging);

    /// <summary>
    /// Konsoldan fişe giden kablo. Görseldeki kablonun (PS5) son parçasının üstünden başlar ki ek yeri belli olmasın;
    /// Xbox'ta konsolun arkasından çıkar. Fiş çıkıkken fişin ARKASINA fişin ekseni boyunca girer ve boyundan artan
    /// kadar sarkar; takılıyken (<paramref name="seated"/>) alttan prize kıvrılır.
    /// </summary>
    public CableShape Cable(ScenePoint plug, bool seated)
    {
        IReadOnlyList<ScenePoint> lead = CableLead.Count > 0 ? CableLead : [CableStart];
        var start = lead[^1];
        if (seated)
        {
            var end = new ScenePoint(plug.X, plug.Y + 30);
            return new CableShape(lead, new(start.X + CableOut.X * 90, start.Y + CableOut.Y * 90), new(end.X + 10, end.Y + 170), end);
        }
        var prong = Prong(PlugTurn(plug));
        // Fişin arkası: gövdenin üstündeki kablo boğazı.
        var back = new ScenePoint(plug.X - prong.X * 40, plug.Y - prong.Y * 40);
        var sag = Math.Max(0, CableLength - back.DistanceTo(start)) * 0.45;
        return new CableShape(lead,
            new(start.X + CableOut.X * 70, start.Y + CableOut.Y * 70 + sag),
            new(back.X - prong.X * 80, back.Y - prong.Y * 80 + sag),
            back);
    }
}
