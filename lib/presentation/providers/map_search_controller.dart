import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/search_repository.dart';

class MapSearchController extends ChangeNotifier {
  MapSearchController({
    SearchRepository? repository,
    this.onError,
  }) : _repository = repository ?? SearchRepository();

  final SearchRepository _repository;
  final ValueChanged<String>? onError;
  final TextEditingController textController = TextEditingController();

  /// Явный фокус-нод поля поиска.
  ///
  /// Нужен, чтобы после выбора результата (и по тапу вне панели) программно
  /// снять фокус и спрятать клавиатуру. Без собственного нода фокусом владеет
  /// внутренний нод `TextField`, и при открытии/закрытии Drawer или bottom
  /// sheet фреймворк возвращал фокус полю — клавиатура всплывала сама.
  final FocusNode searchFocusNode = FocusNode();

  Timer? _searchDebounce;
  CancelToken? _searchCancelToken;
  int _searchRequestId = 0;
  List<SearchResult> _searchResults = <SearchResult>[];
  bool _searchLoading = false;
  bool _searchNoResults = false;
  bool _searchPanelVisible = false;

  List<SearchResult> get results =>
      List<SearchResult>.unmodifiable(_searchResults);
  bool get loading => _searchLoading;
  bool get noResults => _searchNoResults;
  bool get panelVisible => _searchPanelVisible;

  void onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchCancelToken?.cancel();
    _searchRequestId++;
    final query = value.trim();
    if (query.isEmpty) {
      dismiss();
      return;
    }
    if (query.length < 3) {
      _searchPanelVisible = false;
      _searchLoading = false;
      _searchNoResults = false;
      _searchResults = <SearchResult>[];
      notifyListeners();
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => performSearch(query),
    );
  }

  Future<void> performSearch(String value) async {
    final query = value.trim();
    if (query.length < 3) return;
    _searchCancelToken?.cancel();
    final cancelToken = CancelToken();
    _searchCancelToken = cancelToken;
    final requestId = ++_searchRequestId;
    _searchPanelVisible = true;
    _searchLoading = true;
    _searchNoResults = false;
    notifyListeners();
    try {
      final results = await _repository.searchNominatim(
        query,
        cancelToken: cancelToken,
      );
      if (requestId != _searchRequestId) return;
      _searchResults = results;
      _searchLoading = false;
      _searchNoResults = results.isEmpty;
      _searchPanelVisible = true;
      notifyListeners();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || requestId != _searchRequestId) return;
      _searchLoading = false;
      _searchPanelVisible = false;
      notifyListeners();
      onError?.call('Не удалось выполнить поиск');
    }
  }

  Future<void> loadHistory() async {
    final history = await _repository.getHistory();
    if (history.isEmpty) return;
    _searchResults = history;
    _searchNoResults = false;
    _searchPanelVisible = true;
    notifyListeners();
  }

  void showExistingResults() {
    if (_searchResults.isEmpty && !_searchNoResults) return;
    _searchPanelVisible = true;
    notifyListeners();
  }

  Future<SearchResult> selectResult(SearchResult result) async {
    // Результат выбран — сворачиваем панель И снимаем фокус/клавиатуру, чтобы
    // карта осталась на найденной точке, а последующее открытие меню/листа не
    // возвращало фокус полю.
    dismissAndUnfocus();
    await _repository.addToHistory(result);
    return result;
  }

  void dismiss() {
    _searchDebounce?.cancel();
    _searchCancelToken?.cancel();
    _searchRequestId++;
    _searchPanelVisible = false;
    _searchLoading = false;
    _searchNoResults = false;
    _searchResults = <SearchResult>[];
    notifyListeners();
  }

  /// Свернуть панель и одновременно снять фокус (тап по затемнению, выбор
  /// результата, тап по карте). В отличие от [dismiss] трогает фокус, поэтому
  /// НЕ вызывается из [onSearchChanged] при пустом запросе — там пользователь
  /// продолжает ввод и фокус должен сохраниться.
  void dismissAndUnfocus() {
    searchFocusNode.unfocus();
    dismiss();
  }

  void clear() {
    textController.clear();
    dismiss();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCancelToken?.cancel();
    textController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }
}
