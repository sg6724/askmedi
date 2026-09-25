import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/platform/location_service.dart';
import '../../../core/platform/url_opener.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets.dart';
import '../data/hospitals_repository.dart';
import '../domain/hospital.dart';

/// Hospitals tab: location bar (my location, or PIN code / area), then a list.
class HospitalsScreen extends ConsumerStatefulWidget {
  const HospitalsScreen({super.key});

  @override
  ConsumerState<HospitalsScreen> createState() => _HospitalsScreenState();
}

class _HospitalsScreenState extends ConsumerState<HospitalsScreen> {
  final _place = TextEditingController();
  bool _busy = false;
  String? _error;
  HospitalSearchResult? _result;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await ref.read(locationServiceProvider).current();
      await _search(CoordsQuery(p.lat, p.lng));
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.failure) {
          LocationFailure.denied => l10n.locationDenied,
          LocationFailure.serviceOff => l10n.locationServiceOff,
          LocationFailure.unavailable => l10n.locationUnavailable,
        };
      });
    }
  }

  void _searchText() {
    final t = _place.text.trim();
    if (t.isEmpty) return;
    FocusScope.of(context).unfocus();
    _search(HospitalQuery.fromText(t));
  }

  Future<void> _search(HospitalQuery query) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(hospitalsRepositoryProvider).search(query);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = apiErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabHospitals)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.hospitalsIntro,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _useMyLocation,
            icon: const Icon(Icons.my_location),
            label: Text(l10n.useMyLocation),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _place,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchText(),
                  decoration: InputDecoration(
                    labelText: l10n.pincodeOrArea,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy ? null : _searchText,
                child: Text(l10n.search),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ErrorBanner(_error!),
          if (result != null && !_busy) ...[
            if (result.label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.hospitalsNear(result.label),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if (result.hospitals.isEmpty)
              EmptyState(l10n.noHospitals, icon: Icons.local_hospital_outlined),
            for (final h in result.hospitals) HospitalCard(hospital: h),
          ],
        ],
      ),
    );
  }
}

class HospitalCard extends ConsumerWidget {
  const HospitalCard({super.key, required this.hospital});
  final Hospital hospital;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final open = ref.read(urlOpenerProvider);
    final h = hospital;
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    h.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (h.distanceKm != null)
                  Text(
                    l10n.distanceKm(h.distanceKm!.toStringAsFixed(1)),
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (h.address != null && h.address!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  h.address!,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            if (h.emergency == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emergency,
                      size: 16,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.emergencyCare,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (h.phone != null && h.phone!.isNotEmpty) ...[
                  OutlinedButton.icon(
                    // OSM may list several numbers; dial the first, digits only.
                    onPressed: () => open(
                      Uri(
                        scheme: 'tel',
                        path: h.phone!
                            .split(RegExp(r'[;,/]'))
                            .first
                            .replaceAll(RegExp(r'[^0-9+]'), ''),
                      ),
                    ),
                    icon: const Icon(Icons.call, size: 18),
                    label: Text(l10n.callButton),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: () => open(Uri.parse(h.directionsUrl)),
                  icon: const Icon(Icons.directions, size: 18),
                  label: Text(l10n.directions),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
