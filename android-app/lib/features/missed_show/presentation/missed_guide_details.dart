// Le détail se consulte à la demande dans le Guide, sans minuterie.
import 'package:flutter/material.dart';

import '../../../core/app/repair_flags.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/missed_summary.dart';

class MissedGuideDetails extends StatelessWidget {
  const MissedGuideDetails({super.key, required this.summary});

  final MissedSummary? summary;

  @override
  Widget build(BuildContext context) {
    final MissedSummary? current = summary;
    final String description = current?.description?.trim() ?? '';
    if (RepairFlags.missedNoticeLegacy ||
        current == null ||
        description.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(current.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.tvNotice),
          const SizedBox(height: 4),
          Text(description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.tvNotice.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}
