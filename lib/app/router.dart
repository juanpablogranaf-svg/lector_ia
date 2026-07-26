import 'package:go_router/go_router.dart';
import '../presentation/library/pages/library_page.dart';
import '../presentation/reader/pages/reader_page.dart';
import '../presentation/settings/pages/settings_page.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(
        path: '/library',
        name: 'library',
        builder: (context, state) => const LibraryPage(),
      ),
      GoRoute(
        path: '/reader/:bookId',
        name: 'reader',
        builder: (context, state) {
          final bookId = state.pathParameters['bookId']!;
          return ReaderPage(bookId: bookId);
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );
}
