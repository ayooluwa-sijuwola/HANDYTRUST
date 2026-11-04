import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/portfolio_project_model.dart';
import '../../providers/portfolio_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';

/// Add or edit a portfolio project.
/// Pass [existing] to enter edit mode; omit for create mode.
class PortfolioProjectScreen extends ConsumerStatefulWidget {
  final String artisanId;
  final PortfolioProjectModel? existing;

  const PortfolioProjectScreen({
    super.key,
    required this.artisanId,
    this.existing,
  });

  @override
  ConsumerState<PortfolioProjectScreen> createState() =>
      _PortfolioProjectScreenState();
}

class _PortfolioProjectScreenState
    extends ConsumerState<PortfolioProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  List<String> _imageUrls = [];
  bool _busy = false;
  final _picker = ImagePicker();

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _titleCtrl.text = widget.existing!.title;
      _descCtrl.text = widget.existing!.description;
      _categoryCtrl.text = widget.existing!.category;
      _imageUrls = List.from(widget.existing!.imageUrls);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<Uint8List> _compress(Uint8List bytes) async {
    if (bytes.lengthInBytes <= 800 * 1024) return bytes;
    return FlutterImageCompress.compressWithList(
      bytes,
      quality: 75,
      format: CompressFormat.jpeg,
    );
  }

  Future<void> _pickImage() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _compress(await picked.readAsBytes());
      final svc = ref.read(portfolioServiceProvider);
      // Upload via StorageService reusing the legacy upload path
      // (we pass index=timestamp to get a unique filename)
      final url = await svc.addImageAndGetUrl(
        artisanId: widget.artisanId,
        bytes: bytes,
      );
      setState(() => _imageUrls.add(url));
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _removeImage(int index) =>
      setState(() => _imageUrls.removeAt(index));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(portfolioServiceProvider);
      if (_isEdit) {
        await svc.updateProject(
          projectId: widget.existing!.id,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          category: _categoryCtrl.text.trim(),
          imageUrls: _imageUrls,
        );
      } else {
        await svc.createProject(
          artisanId: widget.artisanId,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          category: _categoryCtrl.text.trim(),
          imageUrls: _imageUrls,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Project' : 'Add Project'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(
              _isEdit ? 'Update' : 'Save',
              style: TextStyle(
                color: context.colors.primary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(context, 'Project Title'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleCtrl,
                decoration: _inputDec(context, 'e.g. Kitchen Renovation'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              _label(context, 'Category'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _categoryCtrl,
                decoration: _inputDec(context, 'e.g. Plumbing, Electrical'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              _label(context, 'Description'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                decoration: _inputDec(context, 'Describe the project…'),
                maxLines: 4,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              _label(context, 'Photos'),
              const SizedBox(height: 12),
              _photoGrid(context),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: context.colors.textInverse,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          _isEdit ? 'Update Project' : 'Save Project',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
          fontFamily: 'Inter',
        ),
      );

  InputDecoration _inputDec(BuildContext context, String hint) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.colors.textTertiary),
        filled: true,
        fillColor: context.colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.primary, width: 1.5),
        ),
      );

  Widget _photoGrid(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ..._imageUrls.asMap().entries.map((e) => _photoTile(context, e.key)),
        if (_imageUrls.length < 6)
          GestureDetector(
            onTap: _busy ? null : _pickImage,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.colors.borderLight),
              ),
              child: _busy
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Icon(Icons.add_photo_alternate_outlined,
                      color: context.colors.textTertiary),
            ),
          ),
      ],
    );
  }

  Widget _photoTile(BuildContext context, int index) => Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              _imageUrls[index],
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      );
}
