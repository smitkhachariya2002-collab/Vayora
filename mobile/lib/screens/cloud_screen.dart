import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/measurement.dart';
import '../theme.dart';
import 'login_sheet.dart';
import 'premium_screen.dart';

String fmtBytes(num b) {
  if (b >= 1 << 40) return '${(b / (1 << 40)).toStringAsFixed(2)} TB';
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(b / 1024).round()} KB';
}

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});
  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  double? _progress;

  @override
  void initState() {
    super.initState();
    // AppScope can't be read in initState; wait for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _load(); });
  }

  bool? _wasGuest;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload the file list when the user logs in or out.
    final g = AppScope.of(context).status.isGuest;
    if (_wasGuest != null && _wasGuest != g) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _load(); });
    _wasGuest = g;
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    if (app.status.isGuest) {
      _files = [];
    } else {
      try {
        final d = await sb.from('cloud_files').select('id,name,size_bytes,mime,created_at').order('created_at', ascending: false);
        _files = List<Map<String, dynamic>>.from(d);
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<Map<String, dynamic>> _fn(Map<String, dynamic> body) async {
    final r = await sb.functions.invoke('cloud-files', body: body);
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<void> _upload() async {
    if (!await requireAccount(context) || !mounted) return;
    final pick = await FilePicker.platform.pickFiles(withData: false);
    final f = pick?.files.single;
    if (f == null || f.path == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _progress = 0);
    try {
      final reg = await _fn({'action': 'upload', 'name': f.name, 'size': f.size});
      final up = reg['upload'] as Map;
      final file = reg['file'] as Map;
      await sb.storage.from('cloud').uploadToSignedUrl(up['path'] as String, up['token'] as String, File(f.path!));
      await _fn({'action': 'finalize', 'id': file['id']});
      Measurement.instance.track('CloudUploaded',{'media_type':'file'});
      messenger.showSnackBar(const SnackBar(content: Text('Uploaded')));
    } on FunctionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.status == 403 || e.status == 413 ? 'Storage full or not allowed' : 'Upload failed')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Upload failed')));
    }
    if (!mounted) return;
    setState(() => _progress = null);
    await AppScope.of(context).refresh();
    await _load();
  }

  void _fail(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _open(String id) async {
    try {
      final r = await _fn({'action': 'download', 'id': id});
      await launchUrl(Uri.parse(r['url'] as String), mode: LaunchMode.externalApplication);
    } catch (_) {
      _fail('Could not open this file. Please try again.');
    }
  }

  Future<void> _delete(String id) async {
    final app = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete file?'),
        content: const Text('This cannot be undone.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete'))],
      ),
    );
    if (ok != true) return;
    try {
      await _fn({'action': 'delete', 'id': id});
      Measurement.instance.track('CloudDeleted',{'media_type':'file'});
    } catch (_) {
      _fail('Could not delete this file. Please try again.');
    }
    await app.refresh();
    await _load();
  }

  Future<void> _rename(Map<String, dynamic> f) async {
    final c = TextEditingController(text: f['name'] as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: c),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      try {
        await sb.from('cloud_files').update({'name': c.text.trim()}).eq('id', f['id']);
      } catch (_) {
        _fail('Could not rename this file.');
      }
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.status;
    final quota = s.quotaBytes;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: quota > 0 ? FloatingActionButton.extended(onPressed: _upload, icon: const Icon(Icons.upload), label: const Text('Upload')) : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 88), children: [
              const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Cloud', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Storage', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: quota == 0 ? 0 : (s.usedBytes / quota).clamp(0.0, 1.0), minHeight: 8, backgroundColor: Tokens.border)),
                const SizedBox(height: 8),
                Text('${fmtBytes(s.usedBytes)} of ${fmtBytes(quota)} used', style: const TextStyle(color: Tokens.muted, fontSize: 13)),
                if (_progress != null) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              ]))),
              if (s.isGuest)
                _Prompt(text: s.isPremium ? 'Add your email to start using your cloud storage' : 'Add an email to save your account', button: s.isPremium ? 'Add email' : 'Log in', onTap: () async { await requireAccount(context); await _load(); })
              else if (quota == 0 && app.showPrices)
                _Prompt(text: 'Get 2 TB with Premium', button: 'See plans', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())))
              else if (quota == 0)
                const _Prompt(text: 'Cloud storage is not available on your account yet.'),
              if (!s.isGuest && quota > 0 && _files.isEmpty)
                const _Prompt(text: 'No files yet. Tap Upload to add your first file.'),
              for (final f in _files)
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(f['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(fmtBytes((f['size_bytes'] as num?) ?? 0), style: const TextStyle(color: Tokens.muted)),
                  onTap: () => _open(f['id'] as String),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => v == 'rename' ? _rename(f) : _delete(f['id'] as String),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                  ),
                ),
            ]),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.text, this.button, this.onTap});
  final String text;
  final String? button;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(children: [
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Tokens.muted)),
          if (button != null) Padding(padding: const EdgeInsets.only(top: 10), child: GradientButton(label: button!, onPressed: onTap)),
        ]),
      );
}

