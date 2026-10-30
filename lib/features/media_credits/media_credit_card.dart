import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/web_safe_image.dart';
import '../auth/widgets/phone_input.dart';
import 'media_credit.dart';

/// Medya sekmesindeki künye etiketi ("Fotoğraf: Ekrem Ayyüz"). Turnuvanın o
/// türden etkin künyesi yoksa hiçbir şey çizmez. Önce bellekteki/cihazdaki
/// hâl çizilir, sonra veritabanından tazelenir.
class MediaCreditChip extends StatefulWidget {
  const MediaCreditChip({
    super.key,
    required this.leagueId,
    required this.kind,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 0),
    this.asRow = false,
  });

  final String leagueId;
  final MediaCreditKind kind;
  final EdgeInsets padding;

  /// Maç bilgisi kartında: çerçevesiz satır (ikon · etiket · ad).
  final bool asRow;

  @override
  State<MediaCreditChip> createState() => _MediaCreditChipState();
}

class _MediaCreditChipState extends State<MediaCreditChip> {
  late List<MediaCredit>? _credits = MediaCreditFeed.memory(widget.leagueId);

  @override
  void initState() {
    super.initState();
    MediaCreditFeed.changes.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    MediaCreditFeed.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (MediaCreditFeed.changes.value == widget.leagueId) _load(fresh: true);
  }

  Future<void> _load({bool fresh = false}) async {
    if (!fresh && _credits == null) {
      final c = await MediaCreditFeed.cached(widget.leagueId);
      if (mounted && c != null) setState(() => _credits = c);
    }
    try {
      final c = await MediaCreditFeed.fetch(widget.leagueId);
      if (mounted) setState(() => _credits = c);
    } catch (_) {
      // Ağ hatasında eldeki hâl kalır.
    }
  }

  @override
  Widget build(BuildContext context) {
    final credit = _credits
        ?.where((c) => c.kind == widget.kind && c.isActive)
        .firstOrNull;
    if (credit == null) return const SizedBox.shrink();
    if (widget.asRow) {
      return InkWell(
        onTap: () => showMediaCreditCard(context, credit),
        child: Padding(
          padding: widget.padding,
          child: MatchInfoLine(
            icon: credit.kind == MediaCreditKind.photo
                ? Icons.photo_camera_outlined
                : Icons.videocam_outlined,
            label: credit.kind.label,
            value: credit.name,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.white38,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: widget.padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: const Color(0xFF1E293B),
          shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showMediaCreditCard(context, credit),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    credit.kind == MediaCreditKind.photo
                        ? Icons.photo_camera_outlined
                        : Icons.videocam_outlined,
                    size: 16,
                    color: kAdminAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${credit.kind.chipLabel}: ',
                    style: const TextStyle(
                      color: kAdminMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      credit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 0532… / 532… / +90532… → 905321234567 (WhatsApp ve arama için).
String? _phoneDigits(String? phone) {
  var d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('0')) d = d.substring(1);
  if (d.length == 10) d = '90$d';
  return d;
}

String _instagramUrl(String handle) {
  final h = handle.trim();
  if (h.startsWith('http')) return h;
  return 'https://instagram.com/${h.replaceFirst('@', '')}';
}

String _instagramHandle(String handle) {
  final h = handle.trim();
  final m = RegExp(r'instagram\.com/([^/?#]+)').firstMatch(h);
  return '@${(m?.group(1) ?? h).replaceFirst('@', '')}';
}

Future<void> _open(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı.')));
    }
  } catch (_) {}
}

/// Künyenin kartviziti: alttan açılır.
Future<void> showMediaCreditCard(BuildContext context, MediaCredit credit) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1E293B),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _MediaCreditCard(credit: credit),
  );
}

class _MediaCreditCard extends StatelessWidget {
  const _MediaCreditCard({required this.credit});

  final MediaCredit credit;

  @override
  Widget build(BuildContext context) {
    final c = credit;
    final digits = c.contactConsent ? _phoneDigits(c.phone) : null;
    final email = c.contactConsent ? c.email : null;
    final initials = c.name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();

    // Uygulamaların kendi simgeleri (telefon, WhatsApp, Instagram).
    final actions = <(Widget, String, String)>[
      if (digits != null) (_BrandIcon.phone, 'Ara', 'tel:+$digits'),
      if (digits != null)
        (_BrandIcon.whatsapp, 'WhatsApp', 'https://wa.me/$digits'),
      if (email != null) (_BrandIcon.mail, 'E-posta', 'mailto:$email'),
      if (c.instagram != null)
        (_BrandIcon.instagram, 'Instagram', _instagramUrl(c.instagram!)),
    ];

    final details = <(String, String)>[
      if (c.contactConsent && c.phone != null)
        ('Telefon', formatPhoneRaw10(normalizePhoneToRaw10(c.phone!))),
      if (email != null) ('E-posta', email),
      if (c.instagram != null) ('Instagram', _instagramHandle(c.instagram!)),
    ];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF064E3B),
                    border: Border.all(color: kAdminAccent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: c.avatarUrl != null
                      ? WebSafeImage(
                          url: c.avatarUrl!,
                          fit: BoxFit.cover,
                          width: 64,
                          height: 64,
                        )
                      : Text(
                          initials,
                          style: const TextStyle(
                            color: Color(0xFFA7F3D0),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.displayTitle,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (c.youtubeUrl != null) ...[
              const SizedBox(height: 18),
              Material(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _open(context, c.youtubeUrl!),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Row(
                      children: [
                        FaIcon(
                          FontAwesomeIcons.youtube,
                          color: Color(0xFFFF0000),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'YouTube kanalı',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white38,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Material(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _open(context, actions[i].$3),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              children: [
                                actions[i].$1,
                                const SizedBox(height: 8),
                                Text(
                                  actions[i].$2,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (details.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final d in details)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Text(
                        d.$1,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SelectableText(
                          d.$2,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (c.note != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  c.note!,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Maç bilgisi satırı: ikon, soluk etiket ve kalın değer.
class MatchInfoLine extends StatelessWidget {
  const MatchInfoLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: kAdminAccent),
        const SizedBox(width: 10),
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: const TextStyle(
              color: kAdminMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// İletişim düğmesinin simgesi: uygulamanın kendi renginde yuvarlatılmış
/// kare içinde beyaz logo.
class _BrandIcon extends StatelessWidget {
  const _BrandIcon({required this.icon, this.color, this.gradient});

  final IconData icon;
  final Color? color;
  final Gradient? gradient;

  static const phone = _BrandIcon(
    icon: Icons.call_rounded,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF5BE374), Color(0xFF1FB94A)],
    ),
  );
  static const whatsapp = _BrandIcon(
    icon: FontAwesomeIcons.whatsapp,
    color: Color(0xFF25D366),
  );
  static const mail = _BrandIcon(
    icon: Icons.mail_rounded,
    color: Color(0xFF1E88E5),
  );
  static const instagram = _BrandIcon(
    icon: FontAwesomeIcons.instagram,
    gradient: RadialGradient(
      center: Alignment(-0.6, 1.2),
      radius: 1.5,
      colors: [
        Color(0xFFFEDA75),
        Color(0xFFFA7E1E),
        Color(0xFFD62976),
        Color(0xFF962FBF),
        Color(0xFF4F5BD5),
      ],
      stops: [0, 0.25, 0.5, 0.75, 1],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: BorderRadius.circular(11),
      ),
      child: FaIcon(icon, color: Colors.white, size: 22),
    );
  }
}
