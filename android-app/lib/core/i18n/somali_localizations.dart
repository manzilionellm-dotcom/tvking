// Flutter ne livre pas encore les widgets en somali. Ces délégués gardent
// les champs, leurs menus et les annonces accessibles dans la même langue
// que le catalogue de l'app, sans replier toute la page sur l'anglais.
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'somali_formats.dart';

const somaliLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  _SomaliMaterialDelegate(),
  _SomaliWidgetsDelegate(),
  _SomaliCupertinoDelegate(),
];

class SomaliMaterialLocalizations extends DefaultMaterialLocalizations {
  const SomaliMaterialLocalizations();
  @override
  String get dateHelpText => "dd/MM/yyyy";
  @override
  String get selectYearSemanticsLabel => "Dooro sanadka";
  @override
  String get unspecifiedDate => "Taariikh";
  @override
  String get unspecifiedDateRange => "Muddada taariikhaha";
  @override
  String get dateInputLabel => "Geli taariikhda";
  @override
  String get dateRangeStartLabel => "Taariikhda bilowga";
  @override
  String get dateRangeEndLabel => "Taariikhda dhammaadka";
  @override
  String get invalidDateFormatLabel => "Qaab aan sax ahayn.";
  @override
  String get invalidDateRangeLabel => "Muddo aan sax ahayn.";
  @override
  String get dateOutOfRangeLabel => "Ka baxsan muddada.";
  @override
  String get saveButtonLabel => "Kaydi";
  @override
  String get datePickerHelpText => "Dooro taariikhda";
  @override
  String get dateRangePickerHelpText => "Dooro muddada";
  @override
  String get calendarModeButtonLabel => "U beddel jadwalka";
  @override
  String get inputDateModeButtonLabel => "U beddel gelinta";
  @override
  String get timePickerDialHelpText => "Dooro waqtiga";
  @override
  String get timePickerInputHelpText => "Geli waqtiga";
  @override
  String get timePickerHourLabel => "Saacad";
  @override
  String get timePickerMinuteLabel => "Daqiiqad";
  @override
  String get invalidTimeLabel => "Geli waqti sax ah";
  @override
  String get dialModeButtonLabel => "U beddel doorashada saacadda";
  @override
  String get inputTimeModeButtonLabel => "U beddel qoraalka";
  @override
  String get openAppDrawerTooltip => "Fur liiska hagidda";
  @override
  String get backButtonTooltip => "Dib u noqo";
  @override
  String get clearButtonTooltip => "Tirtir qoraalka";
  @override
  String get closeButtonTooltip => "Xir";
  @override
  String get deleteButtonTooltip => "Tirtir";
  @override
  String get moreButtonTooltip => "Dheeraad";
  @override
  String get nextMonthTooltip => "Bisha xigta";
  @override
  String get previousMonthTooltip => "Bishii hore";
  @override
  String get nextPageTooltip => "Bogga xiga";
  @override
  String get previousPageTooltip => "Boggii hore";
  @override
  String get firstPageTooltip => "Bogga koowaad";
  @override
  String get lastPageTooltip => "Bogga ugu dambeeya";
  @override
  String get showMenuTooltip => "Muuji liiska";
  @override
  String get drawerLabel => "Liiska hagidda";
  @override
  String get menuBarMenuLabel => "Liiska barxadda";
  @override
  String get popupMenuLabel => "Liiska soo baxa";
  @override
  String get dialogLabel => "Wadahadal";
  @override
  String get alertDialogLabel => "Digniin";
  @override
  String get searchFieldLabel => "Raadi";
  @override
  String get currentDateLabel => "Maanta";
  @override
  String get selectedDateLabel => "La doortay";
  @override
  String get scrimLabel => "Daboolka";
  @override
  String get bottomSheetLabel => "Daaqadda hoose";
  @override
  String get licensesPageTitle => "Shatiyada";
  @override
  String get rowsPerPageTitle => "Safka bog kasta:";
  @override
  String get cancelButtonLabel => "Jooji";
  @override
  String get closeButtonLabel => "Xir";
  @override
  String get continueButtonLabel => "Sii wad";
  @override
  String get copyButtonLabel => "Nuqul ka samee";
  @override
  String get cutButtonLabel => "Jar";
  @override
  String get scanTextButtonLabel => "Sawir qoraalka";
  @override
  String get okButtonLabel => "Hagaag";
  @override
  String get pasteButtonLabel => "Ku dheji";
  @override
  String get selectAllButtonLabel => "Dooro dhammaan";
  @override
  String get lookUpButtonLabel => "Ka raadi";
  @override
  String get searchWebButtonLabel => "Ka raadi shabakadda";
  @override
  String get shareButtonLabel => "La wadaag";
  @override
  String get viewLicensesButtonLabel => "Eeg shatiyada";
  @override
  String get anteMeridiemAbbreviation => "GH";
  @override
  String get postMeridiemAbbreviation => "GD";
  @override
  String get timePickerHourModeAnnouncement => "Dooro saacadaha";
  @override
  String get timePickerMinuteModeAnnouncement => "Dooro daqiiqadaha";
  @override
  String get modalBarrierDismissLabel => "Xir";
  @override
  String get menuDismissLabel => "Xir liiska";
  @override
  String get signedInLabel => "Waa la galay";
  @override
  String get hideAccountsLabel => "Qari akoonnada";
  @override
  String get showAccountsLabel => "Muuji akoonnada";
  @override
  String get reorderItemUp => "Kor u dhaqaaji";
  @override
  String get reorderItemDown => "Hoos u dhaqaaji";
  @override
  String get reorderItemLeft => "Bidix u dhaqaaji";
  @override
  String get reorderItemRight => "Midig u dhaqaaji";
  @override
  String get reorderItemToEnd => "U dhaqaaji dhammaadka";
  @override
  String get reorderItemToStart => "U dhaqaaji bilowga";
  @override
  String get expandedIconTapHint => "Yaree";
  @override
  String get collapsedIconTapHint => "Ballaadhi";
  @override
  String get expansionTileExpandedHint => "Laba jeer taabo si aad u yarayso";
  @override
  String get expansionTileCollapsedHint =>
      "Laba jeer taabo si aad u ballaadhiso";
  @override
  String get expansionTileExpandedTapHint => "Yaree";
  @override
  String get expansionTileCollapsedTapHint =>
      "Ballaadhi si aad faahfaahin u aragto";
  @override
  String get expandedHint => "La yareeyey";
  @override
  String get collapsedHint => "La ballaadhiyey";
  @override
  String get refreshIndicatorSemanticLabel => "Cusboonaysii";
  @override
  String get keyboardKeyBackspace => "Dib u tirtir";
  @override
  String get keyboardKeyCapsLock => "Xarfaha waaweyn";
  @override
  String get keyboardKeyChannelDown => "Kanaalka hore";
  @override
  String get keyboardKeyChannelUp => "Kanaalka xiga";
  @override
  String get keyboardKeyDelete => "Tirtir";
  @override
  String get keyboardKeyEject => "Saar";
  @override
  String get keyboardKeyEnd => "Dhammaad";
  @override
  String get keyboardKeyHome => "Bilow";
  @override
  String get keyboardKeyInsert => "Geli";
  @override
  String get keyboardKeyPageDown => "Bogga xiga";
  @override
  String get keyboardKeyPageUp => "Boggii hore";
  @override
  String get keyboardKeyPower => "Awood";
  @override
  String get keyboardKeyPowerOff => "Dami";
  @override
  String get keyboardKeyPrintScreen => "Sawir shaashadda";
  @override
  String get keyboardKeyScrollLock => "Quful rogista";
  @override
  String get keyboardKeySelect => "Dooro";
  @override
  String get keyboardKeySpace => "Bannaan";
  @override
  String scrimOnTapHint(String modalRouteContentName) =>
      'Xir $modalRouteContentName';
  @override
  String aboutListTileTitle(String applicationName) =>
      'Ku saabsan $applicationName';
  @override
  String licensesPackageDetailText(int licenseCount) => '$licenseCount shati';
  @override
  String pageRowsInfoTitle(int firstRow, int lastRow, int rowCount,
          bool rowCountIsApproximate) =>
      rowCountIsApproximate
          ? '$firstRow–$lastRow oo ka mid ah qiyaastii $rowCount'
          : '$firstRow–$lastRow oo ka mid ah $rowCount';
  @override
  String tabLabel({required int tabIndex, required int tabCount}) =>
      'Qaybta $tabIndex ee $tabCount';
  @override
  String selectedRowCountTitle(int selectedRowCount) =>
      '$selectedRowCount shay ayaa la doortay';
  @override
  String remainingTextFieldCharacterCount(int remaining) =>
      '$remaining xaraf ayaa hadhay';
  @override
  String dateRangeStartDateSemanticLabel(String formattedDate) =>
      'Taariikhda bilowga $formattedDate';
  @override
  String dateRangeEndDateSemanticLabel(String formattedDate) =>
      'Taariikhda dhammaadka $formattedDate';
  // Même ordre jour/mois que les formats affichés par intl. Une saisie
  // impossible (31 février) est refusée plutôt que normalisée au mois suivant.
  @override
  String formatCompactDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';
  @override
  DateTime? parseCompactDate(String? inputString) {
    if (inputString == null) return null;
    final parts = inputString.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null ||
        month == null ||
        year == null ||
        year < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  @override
  int get firstDayOfWeekIndex => 6; // samedi ; intl compte depuis lundi.

  @override
  String formatShortDate(DateTime date) => DateFormat.yMMMd('so').format(date);
  @override
  String formatMediumDate(DateTime date) => DateFormat.MMMEd('so').format(date);
  @override
  String formatFullDate(DateTime date) =>
      DateFormat.yMMMMEEEEd('so').format(date);
  @override
  String formatMonthYear(DateTime date) => DateFormat.yMMMM('so').format(date);
  @override
  String formatShortMonthDay(DateTime date) =>
      DateFormat.MMMd('so').format(date);
  @override
  List<String> get narrowWeekdays => const ['A', 'I', 'T', 'A', 'K', 'J', 'S'];
}

class _SomaliMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _SomaliMaterialDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'so';
  @override
  Future<MaterialLocalizations> load(Locale locale) {
    initializeSomaliFormats();
    return SynchronousFuture<MaterialLocalizations>(
        const SomaliMaterialLocalizations());
  }

  @override
  bool shouldReload(_SomaliMaterialDelegate old) => false;
}

class SomaliWidgetsLocalizations extends DefaultWidgetsLocalizations {
  const SomaliWidgetsLocalizations();
  @override
  String get copyButtonLabel => "Nuqul ka samee";
  @override
  String get cutButtonLabel => "Jar";
  @override
  String get pasteButtonLabel => "Ku dheji";
  @override
  String get selectAllButtonLabel => "Dooro dhammaan";
  @override
  String get lookUpButtonLabel => "Ka raadi";
  @override
  String get searchWebButtonLabel => "Ka raadi shabakadda";
  @override
  String get shareButtonLabel => "La wadaag";
  @override
  String get reorderItemUp => "Kor u dhaqaaji";
  @override
  String get reorderItemDown => "Hoos u dhaqaaji";
  @override
  String get reorderItemLeft => "Bidix u dhaqaaji";
  @override
  String get reorderItemRight => "Midig u dhaqaaji";
  @override
  String get reorderItemToEnd => "U dhaqaaji dhammaadka";
  @override
  String get reorderItemToStart => "U dhaqaaji bilowga";
  @override
  String get searchResultsFound => "Natiijooyin raadis ayaa la helay";
  @override
  String get noResultsFound => "Natiijooyin lama helin";
  @override
  String get radioButtonUnselectedLabel => "Lama dooran";
}

class _SomaliWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _SomaliWidgetsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'so';
  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    initializeSomaliFormats();
    return SynchronousFuture<WidgetsLocalizations>(
        const SomaliWidgetsLocalizations());
  }

  @override
  bool shouldReload(_SomaliWidgetsDelegate old) => false;
}

class SomaliCupertinoLocalizations extends DefaultCupertinoLocalizations {
  const SomaliCupertinoLocalizations();
  @override
  String get alertDialogLabel => "Digniin";
  @override
  String get cancelButtonLabel => "Jooji";
  @override
  String get copyButtonLabel => "Nuqul ka samee";
  @override
  String get cutButtonLabel => "Jar";
  @override
  String get pasteButtonLabel => "Ku dheji";
  @override
  String get selectAllButtonLabel => "Dooro dhammaan";
  @override
  String get lookUpButtonLabel => "Ka raadi";
  @override
  String get searchWebButtonLabel => "Ka raadi shabakadda";
  @override
  String get shareButtonLabel => "La wadaag";
  @override
  String get anteMeridiemAbbreviation => "GH";
  @override
  String get postMeridiemAbbreviation => "GD";
  @override
  String get modalBarrierDismissLabel => "Xir";
  @override
  String get menuDismissLabel => "Xir liiska";
  @override
  String get expansionTileExpandedHint => "Laba jeer taabo si aad u yarayso";
  @override
  String get expansionTileCollapsedHint =>
      "Laba jeer taabo si aad u ballaadhiso";
  @override
  String get expansionTileExpandedTapHint => "Yaree";
  @override
  String get expansionTileCollapsedTapHint =>
      "Ballaadhi si aad faahfaahin u aragto";
  @override
  String get expandedHint => "La yareeyey";
  @override
  String get collapsedHint => "La ballaadhiyey";
  @override
  String get clearButtonLabel => "Tirtir";
  @override
  String get noSpellCheckReplacementsLabel => "Beddel lama helin";
  @override
  String get searchTextFieldPlaceholderLabel => "Raadi";
  @override
  String get backButtonLabel => "Dib u noqo";
  @override
  String get todayLabel => "Maanta";
  @override
  DatePickerDateOrder get datePickerDateOrder => DatePickerDateOrder.dmy;
  @override
  String datePickerMonth(int monthIndex) => somaliMonths[monthIndex - 1];
  @override
  String datePickerStandaloneMonth(int monthIndex) =>
      somaliMonths[monthIndex - 1];
  @override
  String datePickerDayOfMonth(int dayIndex, [int? weekDay]) => weekDay == null
      ? '$dayIndex'
      : '${somaliWeekdays[weekDay % 7]} $dayIndex';
  @override
  String datePickerMediumDate(DateTime date) =>
      DateFormat.MMMEd('so').format(date);
  @override
  String datePickerHourSemanticsLabel(int hour) => 'Saacadda $hour';
  @override
  String datePickerMinuteSemanticsLabel(int minute) => '$minute daqiiqadood';
  @override
  String tabSemanticsLabel({required int tabIndex, required int tabCount}) =>
      'Qaybta $tabIndex ee $tabCount';
  @override
  String timerPickerHourLabel(int hour) => 'saac';
  @override
  List<String> get timerPickerHourLabels => const ['saac'];
  @override
  String timerPickerMinuteLabel(int minute) => 'daqiiqo';
  @override
  List<String> get timerPickerMinuteLabels => const ['daqiiqo'];
  @override
  String timerPickerSecondLabel(int second) => 'ilbiriqsi';
  @override
  List<String> get timerPickerSecondLabels => const ['ilbiriqsi'];
}

class _SomaliCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _SomaliCupertinoDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'so';
  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    initializeSomaliFormats();
    return SynchronousFuture<CupertinoLocalizations>(
        const SomaliCupertinoLocalizations());
  }

  @override
  bool shouldReload(_SomaliCupertinoDelegate old) => false;
}
