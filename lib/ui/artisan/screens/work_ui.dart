import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/artisan_work_logic.dart';
import '../../../models/job_model.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../components/pro_components.dart';

/// Shared presentation helpers for the artisan work screens.

/// Jobs have no title field: use the first line of the description.
String workTitle(JobModel j) {
  final first = j.description.trim().split('\n').first.trim();
  if (first.isEmpty) return j.category;
  return first.length > 60 ? '${first.substring(0, 57)}…' : first;
}

HtTone stageTone(ArtisanStage s) => switch (s) {
      ArtisanStage.request || ArtisanStage.disputed => HtTone.danger,
      ArtisanStage.agreement || ArtisanStage.schedule || ArtisanStage.rework => HtTone.warning,
      ArtisanStage.awaitingPayment => HtTone.neutral,
      ArtisanStage.readyToStart || ArtisanStage.completed => HtTone.success,
      ArtisanStage.working => HtTone.warning,
      ArtisanStage.inReview => HtTone.accent,
      ArtisanStage.closed => HtTone.neutral,
    };

IconData categoryIcon(String category) {
  final c = category.toLowerCase();
  if (c.contains('plumb')) return Icons.plumbing_rounded;
  if (c.contains('electr')) return Icons.electrical_services_rounded;
  if (c.contains('paint')) return Icons.format_paint_outlined;
  if (c.contains('carpent')) return Icons.carpenter_rounded;
  if (c.contains('clean')) return Icons.cleaning_services_outlined;
  if (c.contains('weld')) return Icons.local_fire_department_outlined;
  if (c.contains('til')) return Icons.grid_on_rounded;
  if (c.contains('generator')) return Icons.electric_bolt_rounded;
  if (c.contains('renovat')) return Icons.home_repair_service_outlined;
  if (c.contains('security')) return Icons.security_rounded;
  if (c.contains('landscap')) return Icons.yard_outlined;
  return Icons.handyman_outlined;
}

/// Pick one gallery photo, compressing large files exactly as the previous
/// artisan screens did (JPEG q70 above 500 KB). EXIF is stripped later by
/// StorageService on upload.
Future<Uint8List?> pickWorkPhoto() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final raw = await picked.readAsBytes();
  if (raw.lengthInBytes <= 500 * 1024) return raw;
  return Uint8List.fromList(await FlutterImageCompress.compressWithList(raw, quality: 70));
}

/// Deadline text for a job ticket, from server-backed times only.
String? ticketDeadline(JobModel j, int bookingHours, DateTime now) {
  final booking = ArtisanWorkLogic.bookingDeadline(j, bookingHours);
  if (booking != null) {
    final left = ArtisanWorkLogic.remainingLabel(booking, now);
    return left == null ? 'Response window ended' : 'Respond within $left';
  }
  final review = ArtisanWorkLogic.reviewEnds(j);
  if (review != null) return 'Auto-release ${HtFormat.date(review.toLocal())}';
  return null;
}

/// Primary ticket action label per stage (opens the work order).
String? ticketAction(JobModel j) => switch (ArtisanWorkLogic.stageOf(j)) {
      ArtisanStage.request => 'Respond',
      ArtisanStage.agreement => j.agreementStatus == AgreementStatus.pendingArtisanConfirmation ? 'Review agreement' : 'View',
      ArtisanStage.schedule => j.appointmentSlots.isEmpty ? 'Propose times' : 'View',
      ArtisanStage.readyToStart => 'Start work',
      ArtisanStage.working => 'Update progress',
      ArtisanStage.rework => 'Respond',
      ArtisanStage.disputed => 'Open dispute',
      _ => 'View',
    };

/// Ticket date block: confirmed appointment, else preferred date, else ASAP.
(String, String) ticketDate(JobModel j) {
  final d = j.confirmedAppointment?.toLocal() ?? j.scheduledDate?.toLocal();
  if (d != null) return (proDay(d), proMonth(d));
  return ('', j.urgency == 'asap' ? 'ASAP' : 'TBC');
}

/// Area line for a job: area label, else category.
String jobArea(JobModel j) => j.areaLabel ?? j.category;
