import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../core/theme/app_theme.dart';
import '../presentation/library/bloc/library_bloc.dart';
import '../presentation/reader/bloc/reader_bloc.dart';
import 'router.dart';

class LectorIaApp extends StatelessWidget {
  const LectorIaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => GetIt.I<LibraryBloc>()..add(const LibraryScanStarted())),
        BlocProvider(create: (_) => GetIt.I<ReaderBloc>()),
      ],
      child: BlocBuilder<LibraryBloc, LibraryState>(
        buildWhen: (prev, curr) => prev.themeMode != curr.themeMode,
        builder: (context, state) {
          return MaterialApp.router(
            title: 'LectorIA',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: state.themeMode,
            routerConfig: AppRouter.router,
          );
        },
      ),
    );
  }
}
