import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../application/onboarding_providers.dart';
import 'widgets/onboarding_illustration.dart';
import 'widgets/onboarding_page_indicator.dart';

// ── Data ──────────────────────────────────────────────────────────────────────

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.title,
    required this.description,
    required this.illustrationIndex,
  });

  final String title;
  final String description;
  final int illustrationIndex;
}

const _pages = [
  _OnboardingPageData(
    title: 'Encontra o jardineiro ideal',
    description:
        'Publica o teu pedido com data e local. Profissionais próximos enviam-te propostas em minutos.',
    illustrationIndex: 0,
  ),
  _OnboardingPageData(
    title: 'Escolhe a melhor proposta',
    description:
        'Compara preços, perfis e disponibilidade. Aceita com um toque e o trabalho fica agendado.',
    illustrationIndex: 1,
  ),
  _OnboardingPageData(
    title: 'Trabalho feito, sem complicações',
    description:
        'Avalia no fim. As tuas estrelas ajudam a comunidade a encontrar os melhores profissionais.',
    illustrationIndex: 2,
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ProJardimOnboardingScreen extends ConsumerStatefulWidget {
  const ProJardimOnboardingScreen({super.key});

  @override
  ConsumerState<ProJardimOnboardingScreen> createState() =>
      _ProJardimOnboardingScreenState();
}

class _ProJardimOnboardingScreenState
    extends ConsumerState<ProJardimOnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  bool get _isLastPage => _currentPage == _pages.length - 1;

  void _advance() {
    if (!_isLastPage) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 330),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _skip() {
    _pageController.animateToPage(
      _pages.length - 1,
      duration: const Duration(milliseconds: 330),
      curve: Curves.easeInOut,
    );
  }

  void _finish() {
    ref.read(hasSeenOnboardingProvider.notifier).markSeen().then((_) {
      if (mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isCompact = MediaQuery.sizeOf(context).height < 700;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _SkipRow(
              isLastPage: _isLastPage,
              onSkip: _skip,
              textTheme: textTheme,
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _OnboardingPage(
                  data: _pages[i],
                  isCompact: isCompact,
                  textTheme: textTheme,
                ),
              ),
            ),
            _BottomBar(
              currentPage: _currentPage,
              pageCount: _pages.length,
              isLastPage: _isLastPage,
              isCompact: isCompact,
              onAdvance: _advance,
              textTheme: textTheme,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Private widgets ───────────────────────────────────────────────────────────

class _SkipRow extends StatelessWidget {
  const _SkipRow({
    required this.isLastPage,
    required this.onSkip,
    required this.textTheme,
  });

  final bool isLastPage;
  final VoidCallback onSkip;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Align(
        alignment: Alignment.centerRight,
        child: AnimatedOpacity(
          opacity: isLastPage ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: isLastPage ? null : onSkip,
              child: Text(
                'Saltar',
                style: textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF888878),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.isCompact,
    required this.textTheme,
  });

  final _OnboardingPageData data;
  final bool isCompact;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final illustrationSize = isCompact ? 160.0 : 220.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SizedBox(height: isCompact ? 8 : 24),
          Expanded(
            flex: isCompact ? 3 : 4,
            child: Center(
              child: OnboardingIllustration(
                index: data.illustrationIndex,
                size: illustrationSize,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF111411),
                    fontWeight: FontWeight.w800,
                    height: 1.16,
                    letterSpacing: -0.65,
                    fontSize: 23,
                  ),
                ),
                SizedBox(height: isCompact ? 8 : 12),
                Text(
                  data.description,
                  style: textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6F746D),
                    height: 1.5,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isCompact ? 4 : 12),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentPage,
    required this.pageCount,
    required this.isLastPage,
    required this.isCompact,
    required this.onAdvance,
    required this.textTheme,
  });

  final int currentPage;
  final int pageCount;
  final bool isLastPage;
  final bool isCompact;
  final VoidCallback onAdvance;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, isCompact ? 16 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OnboardingPageIndicator(
            currentPage: currentPage,
            pageCount: pageCount,
          ),
          SizedBox(height: isCompact ? 16 : 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAdvance,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isLastPage ? 'Começar' : 'Continuar',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
