// Web hata kayıtlarındaki sıkıştırılmış yığın izlerini, o derlemenin kaynak
// haritasıyla gerçek Dart dosya/satırına çevirip `app_errors.stack_decoded`
// sütununa yazar.
//
// Kaynak haritaları yayın betiği (scripts/deploy_web.sh) tarafından
// build_maps/<BUILD_ID>/ altına konur; BUILD_ID hata kaydındaki sürümün
// sonundadır ("1.0.0+2 · 503319e").
//
// Kullanım (proje kökünde, supabase CLI bağlı olmalı):
//   dart run tool/decode_errors.dart          # çözülmemiş web hataları
//   dart run tool/decode_errors.dart --all    # hepsini yeniden çöz
import 'dart:convert';
import 'dart:io';

import 'package:source_map_stack_trace/source_map_stack_trace.dart';
import 'package:source_maps/source_maps.dart';
import 'package:stack_trace/stack_trace.dart';

Future<List<Map<String, dynamic>>> _query(String sql) async {
  final r = await Process.run('supabase', [
    'db',
    'query',
    '--linked',
    sql,
    '-o',
    'json',
  ]);
  if (r.exitCode != 0) {
    throw Exception('supabase db query hata verdi:\n${r.stderr}');
  }
  final out = r.stdout as String;
  final start = out.indexOf('{');
  final end = out.lastIndexOf('}');
  if (start < 0 || end < start) return const [];
  final rows = (jsonDecode(out.substring(start, end + 1)) as Map)['rows'];
  return [for (final row in (rows as List? ?? const [])) (row as Map).cast()];
}

String _sqlText(String s) {
  var tag = r'$dec$';
  var n = 0;
  while (s.contains(tag)) {
    tag = '\$dec${++n}\$';
  }
  return '$tag$s$tag';
}

Future<void> main(List<String> args) async {
  final all = args.contains('--all');
  final rows = await _query(
    "select id, app_version, stack from public.app_errors "
    "where platform = 'web' and coalesce(stack, '') <> ''"
    "${all ? '' : ' and stack_decoded is null'} "
    "order by last_seen desc",
  );
  if (rows.isEmpty) {
    stdout.writeln('Çözülecek web hatası yok.');
    return;
  }

  final maps = <String, Mapping?>{};
  var decoded = 0;
  for (final row in rows) {
    final version = (row['app_version'] ?? '').toString();
    final sep = version.lastIndexOf(' · ');
    final build = sep < 0 ? '' : version.substring(sep + 3).trim();
    if (build.isEmpty) {
      stdout.writeln('${row['id']}: derleme kimliği yok ($version), atlandı');
      continue;
    }
    final mapping = maps.putIfAbsent(build, () {
      final f = File('build_maps/$build/main.dart.js.map');
      if (!f.existsSync()) return null;
      return parse(f.readAsStringSync());
    });
    if (mapping == null) {
      stdout.writeln('${row['id']}: build_maps/$build haritası yok, atlandı');
      continue;
    }

    final raw = (row['stack'] ?? '').toString();
    final String text;
    try {
      final mapped = mapStackTrace(mapping, Trace.parse(raw), minified: true);
      // Okunabilir: Flutter/Dart çekirdeği yerine önce uygulama satırları.
      text = Trace.from(
        mapped,
      ).terse.toString().replaceAll(RegExp(r'(\.\./)+lib/'), 'lib/').trim();
    } catch (e) {
      stdout.writeln('${row['id']}: çözülemedi ($e)');
      continue;
    }
    if (text.isEmpty) continue;
    await _query(
      'update public.app_errors set stack_decoded = ${_sqlText(text)} '
      "where id = '${row['id']}'",
    );
    decoded++;
    stdout.writeln('${row['id']} ($build):\n$text\n');
  }
  stdout.writeln('$decoded / ${rows.length} hata çözüldü.');
}
