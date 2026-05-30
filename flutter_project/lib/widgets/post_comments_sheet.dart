import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services_api/Helper.dart';
import 'package:flutter_application_1/services_api/post_service.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';

Future<int?> showPostCommentsSheet({
  required BuildContext context,
  required int postId,
  required int initialCommentsCount,
  ValueChanged<int>? onCommentsCountChanged,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostCommentsSheet(
      postId: postId,
      initialCommentsCount: initialCommentsCount,
      onCommentsCountChanged: onCommentsCountChanged,
    ),
  );
}

class _PostCommentsSheet extends StatefulWidget {
  final int postId;
  final int initialCommentsCount;
  final ValueChanged<int>? onCommentsCountChanged;

  const _PostCommentsSheet({
    required this.postId,
    required this.initialCommentsCount,
    this.onCommentsCountChanged,
  });

  @override
  State<_PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<_PostCommentsSheet> {
  static const int _limit = 20;

  final PostService _postService = PostService();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<Comment> _comments = [];

  int _skip = 0;
  late int _commentsCount;
  bool _isLoading = false;
  bool _isSending = false;
  bool _hasMore = true;
  String? _error;
  ScrollController? _activeScrollController;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _commentsCount = widget.initialCommentsCount;
    _focusNode.addListener(_onFocusChange);
    _loadCurrentUserId();
    _loadComments();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final id = await _postService.getCurrentUserId();
      if (mounted) setState(() => _currentUserId = id);
    } catch (_) {
      // некритично — просто не покажем кнопку удаления
    }
  }

  Future<void> _deleteComment(Comment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить комментарий?'),
        content: const Text('Комментарий будет удалён без возможности отмены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final idx = _comments.indexWhere((c) => c.id == comment.id);
    if (idx == -1) return;
    final removed = _comments[idx];

    // Оптимистично убираем.
    setState(() {
      _comments.removeAt(idx);
      _commentsCount = (_commentsCount - 1).clamp(0, 1 << 31);
    });
    widget.onCommentsCountChanged?.call(_commentsCount);

    try {
      await _postService.deleteComment(widget.postId, comment.id);
    } catch (e) {
      // Откат при ошибке.
      if (!mounted) return;
      setState(() {
        _comments.insert(idx, removed);
        _commentsCount += 1;
      });
      widget.onCommentsCountChanged?.call(_commentsCount);
      showApiError(context, e);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // При появлении клавиатуры форма ввода поднимается и может перекрыть
    // последние комментарии — прокручиваем список вниз, чтобы они оставались
    // видимыми над полем ввода.
    if (_focusNode.hasFocus) {
      _scrollToBottom();
    }
  }

  Future<void> _loadComments() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final comments =
          await _postService.getComments(widget.postId, _skip, _limit);
      if (!mounted) return;

      final existingIds = _comments.map((comment) => comment.id).toSet();
      final newComments = comments
          .where((comment) => !existingIds.contains(comment.id))
          .toList();

      setState(() {
        _comments.addAll(newComments);
        _skip += comments.length;
        _hasMore = comments.length == _limit;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendComment() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final comment = await _postService.addComment(widget.postId, content);
      if (!mounted) return;

      setState(() {
        if (!_comments.any((item) => item.id == comment.id)) {
          _comments.add(comment);
        }
        _commentsCount += 1;
        _controller.clear();
        _isSending = false;
        _error = null;
      });
      widget.onCommentsCountChanged?.call(_commentsCount);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка добавления комментария: $e')),
      );
    }
  }

  void _scrollToBottom() {
    final controller = _activeScrollController;
    if (controller == null || !controller.hasClients) return;

    // Ждём завершения анимации клавиатуры/паддинга, иначе maxScrollExtent ещё
    // не пересчитан и список не докручивается до конца.
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || !controller.hasClients) return;
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 320 && !_isLoading && _hasMore) {
      _loadComments();
    }
    return false;
  }

  void _close() {
    Navigator.of(context).pop(_commentsCount);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        _activeScrollController = scrollController;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                _CommentsHeader(
                  commentsCount: _commentsCount,
                  onClose: _close,
                ),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScroll,
                    child: _buildCommentsList(scrollController),
                  ),
                ),
                _CommentInput(
                  controller: _controller,
                  focusNode: _focusNode,
                  isSending: _isSending,
                  onSend: _sendComment,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommentsList(ScrollController scrollController) {
    if (_isLoading && _comments.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null && _comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Не удалось загрузить комментарии',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return Center(
        child: Text(
          'Комментариев пока нет',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: _comments.length + (_isLoading || _hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        if (index >= _comments.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final comment = _comments[index];
        return _CommentTile(
          comment: comment,
          canDelete:
              _currentUserId != null && comment.userId == _currentUserId,
          onDelete: () => _deleteComment(comment),
        );
      },
    );
  }
}

class _CommentsHeader extends StatelessWidget {
  final int commentsCount;
  final VoidCallback onClose;

  const _CommentsHeader({
    required this.commentsCount,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Комментарии',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$commentsCount',
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  const _CommentTile({
    required this.comment,
    this.canDelete = false,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final avatarUrl = comment.userAvatarUrl ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.surfaceMuted,
          backgroundImage: avatarUrl.isNotEmpty
              ? CachedNetworkImageProvider(avatarUrl)
              : null,
          child: avatarUrl.isEmpty
              ? const Icon(
                  Icons.person_outline,
                  size: 22,
                  color: AppColors.textSecondary,
                )
              : null,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      comment.userFullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    Helper.formatDateTime(comment.createdAt),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (canDelete)
                    GestureDetector(
                      onTap: onDelete,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.only(left: AppSpacing.xs),
                        child: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                comment.content,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;

  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Написать комментарий',
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton.filled(
                tooltip: 'Отправить',
                onPressed: isSending ? null : onSend,
                icon: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
