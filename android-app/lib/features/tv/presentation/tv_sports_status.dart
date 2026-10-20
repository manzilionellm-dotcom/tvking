// État réseau Sport partagé par la recherche et les matchs. Une panne doit
// rester lisible sur la télé ; « Réessayer » est un choix du client.
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../sports/data/sports_repository.dart';

String sportsFailureText(BuildContext context, SportsFailure failure) =>
    switch (failure.kind) {
      SportsFailureKind.timeout => context.l10n.sportsTimeout,
      SportsFailureKind.network => context.l10n.sportsNetworkError,
      SportsFailureKind.http => context.l10n.sportsHttpError(failure.statusCode ?? 0),
      SportsFailureKind.invalidResponse => context.l10n.sportsInvalidResponse,
      SportsFailureKind.unavailable => context.l10n.sportsUnavailable,
    };

class TvSportsStatus extends StatelessWidget {
  const TvSportsStatus({super.key, this.loading = false, this.failure, this.onRetry});
  final bool loading;
  final SportsFailure? failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(loading ? context.l10n.sportsLoading
          : sportsFailureText(context, failure!),
          style: AppTextStyles.headlineMedium.copyWith(
              color: loading ? AppColors.textSecondary : AppColors.warning)),
      if (!loading && onRetry != null)
        TextButton(onPressed: onRetry,
            child: Text(context.l10n.sportsRetry, style: AppTextStyles.button)),
    ],
  );
}
