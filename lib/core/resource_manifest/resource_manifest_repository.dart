import 'resource_manifest_entry.dart';

/// Domain interface for reading/writing `resource_manifest` rows.
///
/// This is the *only* sanctioned way any ingestion code registers a
/// dataset. CLAUDE.md rule #4: every imported dataset needs a manifest
/// entry, no exceptions — see [SqliteResourceManifestRepository.register]
/// for where that rule is actually enforced.
abstract class ResourceManifestRepository {
  Future<void> register(ResourceManifestEntry entry);

  Future<List<ResourceManifestEntry>> getAll();

  Future<ResourceManifestEntry?> getById(String resourceId);

  Future<List<ResourceManifestEntry>> getByCompatibilityGroup(
    String compatibilityGroup,
  );

  Future<void> updateStatus(String resourceId, ResourceManifestStatus status);
}
