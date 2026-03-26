/// Represents a paginated query result.
class PagedResult<T> {
  /// The items in the current page.
  final List<T> data;

  /// Total number of items across all pages.
  final int total;

  /// Current page number (1-indexed).
  final int page;

  /// Number of items per page.
  final int pageSize;

  /// Total number of pages.
  int get totalPages => (total / pageSize).ceil();

  /// Whether there is a next page.
  bool get hasNextPage => page < totalPages;

  /// Whether there is a previous page.
  bool get hasPreviousPage => page > 1;

  const PagedResult({
    required this.data,
    required this.total,
    required this.page,
    required this.pageSize,
  });
}
