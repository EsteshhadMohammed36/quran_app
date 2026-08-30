/// A single row of the `resource_manifest` table (spec §16, §27).
///
/// Every dataset imported from `quran-assets` or QUL — Quran script, Mushaf
/// layout, tafsir, morphology, audio, fonts — must have exactly one of
/// these before its data is used anywhere else in the app (CLAUDE.md rule
/// #4: "no exceptions, no 'I'll add the manifest later'").
library;

/// Lifecycle status of an imported resource.
///
/// `pending`: registered but not yet downloaded/verified.
/// `active`: downloaded, checksum-verified, and in production use.
/// `deprecated`: superseded by a newer version/revision of the same
/// resource; kept for traceability, no longer read by the app.
enum ResourceManifestStatus {
  pending,
  active,
  deprecated;

  String get value => name;

  static ResourceManifestStatus fromValue(String value) {
    return ResourceManifestStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => throw ArgumentError('Unknown resource status: $value'),
    );
  }
}

class ResourceManifestEntry {
  /// Stable identifier for this resource, e.g. `qpc-v2-glyph-word-by-word`.
  /// Chosen by the caller registering the resource — not auto-generated —
  /// so it stays meaningful in code and query results.
  final String resourceId;

  final String resourceName;

  /// e.g. `quran-assets`, `QUL`.
  final String provider;

  /// e.g. `quran-script`, `mushaf-layout`, `font`, `tafsir`, `morphology`,
  /// `audio`, `translation`.
  final String category;

  final String sourceUrl;

  /// e.g. `json`, `sqlite`, `ttf`, `mp3`.
  final String? downloadFormat;

  final String? versionOrRevision;

  /// When this resource was actually downloaded/retrieved, not when the
  /// manifest row was written.
  final DateTime? retrievedAt;

  final String? licenseOrTermsUrl;

  /// SHA-256 of the downloaded file/package, for integrity verification
  /// (spec §23 step 4: "Verify checksum").
  final String? sha256;

  /// Which table (e.g. `words`) or asset path (e.g. `assets/fonts/...`)
  /// this resource's data ends up in.
  final String? targetTableOrAssetPath;

  /// Groups resources that must be used together as a validated set, e.g.
  /// `madinah-v2-qpc-v2-hafs` (spec §16 example).
  final String? compatibilityGroup;

  final ResourceManifestStatus status;

  /// Attribution text required by the provider/resource, per §27. Required
  /// at release time even though it isn't in the §16 column list verbatim.
  final String? attributionText;

  const ResourceManifestEntry({
    required this.resourceId,
    required this.resourceName,
    required this.provider,
    required this.category,
    required this.sourceUrl,
    this.downloadFormat,
    this.versionOrRevision,
    this.retrievedAt,
    this.licenseOrTermsUrl,
    this.sha256,
    this.targetTableOrAssetPath,
    this.compatibilityGroup,
    this.status = ResourceManifestStatus.pending,
    this.attributionText,
  });

  Map<String, Object?> toMap() {
    return {
      'resource_id': resourceId,
      'resource_name': resourceName,
      'provider': provider,
      'category': category,
      'source_url': sourceUrl,
      'download_format': downloadFormat,
      'version_or_revision': versionOrRevision,
      'retrieved_at': retrievedAt?.toIso8601String(),
      'license_or_terms_url': licenseOrTermsUrl,
      'sha256': sha256,
      'target_table_or_asset_path': targetTableOrAssetPath,
      'compatibility_group': compatibilityGroup,
      'status': status.value,
      'attribution_text': attributionText,
    };
  }

  factory ResourceManifestEntry.fromMap(Map<String, Object?> map) {
    return ResourceManifestEntry(
      resourceId: map['resource_id'] as String,
      resourceName: map['resource_name'] as String,
      provider: map['provider'] as String,
      category: map['category'] as String,
      sourceUrl: map['source_url'] as String,
      downloadFormat: map['download_format'] as String?,
      versionOrRevision: map['version_or_revision'] as String?,
      retrievedAt: map['retrieved_at'] == null
          ? null
          : DateTime.parse(map['retrieved_at'] as String),
      licenseOrTermsUrl: map['license_or_terms_url'] as String?,
      sha256: map['sha256'] as String?,
      targetTableOrAssetPath: map['target_table_or_asset_path'] as String?,
      compatibilityGroup: map['compatibility_group'] as String?,
      status: ResourceManifestStatus.fromValue(map['status'] as String),
      attributionText: map['attribution_text'] as String?,
    );
  }

  ResourceManifestEntry copyWith({
    String? resourceName,
    String? provider,
    String? category,
    String? sourceUrl,
    String? downloadFormat,
    String? versionOrRevision,
    DateTime? retrievedAt,
    String? licenseOrTermsUrl,
    String? sha256,
    String? targetTableOrAssetPath,
    String? compatibilityGroup,
    ResourceManifestStatus? status,
    String? attributionText,
  }) {
    return ResourceManifestEntry(
      resourceId: resourceId,
      resourceName: resourceName ?? this.resourceName,
      provider: provider ?? this.provider,
      category: category ?? this.category,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      downloadFormat: downloadFormat ?? this.downloadFormat,
      versionOrRevision: versionOrRevision ?? this.versionOrRevision,
      retrievedAt: retrievedAt ?? this.retrievedAt,
      licenseOrTermsUrl: licenseOrTermsUrl ?? this.licenseOrTermsUrl,
      sha256: sha256 ?? this.sha256,
      targetTableOrAssetPath:
          targetTableOrAssetPath ?? this.targetTableOrAssetPath,
      compatibilityGroup: compatibilityGroup ?? this.compatibilityGroup,
      status: status ?? this.status,
      attributionText: attributionText ?? this.attributionText,
    );
  }
}
