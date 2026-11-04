import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/portfolio_service.dart';
import '../core/services/storage_service.dart';
import '../models/portfolio_project_model.dart';

final portfolioServiceProvider = Provider<PortfolioService>(
  (ref) => PortfolioService(FirebaseFirestore.instance, StorageService()),
);

/// Live portfolio view count — drives the analytics readout in
/// PortfolioManagerScreen.
final portfolioViewCountProvider =
    StreamProvider.family<int, String>((ref, artisanId) {
  return ref.watch(portfolioServiceProvider).watchViewCount(artisanId);
});

/// Real-time stream of portfolio projects for an artisan, newest-first.
final portfolioProjectsProvider =
    StreamProvider.family<List<PortfolioProjectModel>, String>((ref, artisanId) {
  return ref.watch(portfolioServiceProvider).watchProjects(artisanId);
});
