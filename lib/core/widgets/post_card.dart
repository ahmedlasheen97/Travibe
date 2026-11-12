import 'package:travibe/core/widgets/user_profile_link.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/core/widgets/home_post_caption.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/more_options_button.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/action_icon_button.dart';

class PostCard extends StatefulWidget {
  final bool responsive;
  final bool homePresentation;

  /// Post screen (Figma): no card surface, full caption, "N Likes", bare icons.
  final bool detailPresentation;
  final Object? authorId;
  // Optional identity from an already-confirmed /user read in the same session.
  final Object? currentUserId;
  final int? currentUserSessionRevision;
  final String? postId;
  final bool isSaved;
  final bool isSavePending;
  final VoidCallback? onSaveTap;
  final String name;
  final VoidCallback? onMoreTap;

  /// False when the host shows the ⋮ menu elsewhere (Post screen app bar).
  final bool showMoreButton;
  final VoidCallback? onCommentsTap;
  final VoidCallback? onLikeTap;

  /// Like count tap (opens "Liked by"); never toggles the like.
  final VoidCallback? onLikesCountTap;

  /// Taps on text, images or empty space; buttons keep their own actions.
  final VoidCallback? onOpen;
  final bool isLiked;
  final bool isLikePending;
  final VoidCallback? onShareTap;

  final String? avatar;
  final String time;
  final String text;
  final String? location;
  final String? image; // single image
  final List<String>? images; // carousel
  final String likes;
  final String comments;
  final bool showFollowButton;
  final bool neutralFollowButton;
  final bool isFollowing;
  final bool isFollowPending;
  final VoidCallback? onFollowTap;

  const PostCard({
    super.key,
    required this.name,
    this.postId,
    this.responsive = false,
    this.homePresentation = false,
    this.detailPresentation = false,
    this.authorId,
    this.currentUserId,
    this.currentUserSessionRevision,
    this.isSaved = false,
    this.isSavePending = false,
    this.onSaveTap,
    required this.avatar,
    required this.time,
    required this.text,
    this.location,
    this.image,
    this.images,
    required this.likes,
    required this.comments,
    this.showFollowButton = false,
    this.neutralFollowButton = false,
    this.isFollowing = false,
    this.isFollowPending = false,
    this.onFollowTap,
    this.onMoreTap,
    this.showMoreButton = true,
    this.onCommentsTap,
    this.onLikeTap,
    this.onLikesCountTap,
    this.onOpen,
    this.isLiked = false,
    this.isLikePending = false,
    this.onShareTap,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  int _imageIndex = 0;
  bool _isExpanded = false;

  static const int _collapsedMaxLines = 3;

  double _w(double value) =>
      widget.responsive ? AppSizes.adaptiveWidth(value) : value;
  double _h(double value) =>
      widget.responsive ? AppSizes.adaptiveHeight(value) : value;
  double _r(double value) =>
      widget.responsive ? AppSizes.adaptiveRadius(value) : value;
  double _font(double value) =>
      widget.responsive ? AppSizes.adaptiveFont(value) : value;

  bool get _hasCarousel => widget.images != null && widget.images!.length > 1;
  bool get _hasSingleImage => widget.images == null && widget.image != null;

  @override
  Widget build(BuildContext context) {
    final detail = widget.detailPresentation;
    final card = Container(
      padding: detail ? EdgeInsets.zero : EdgeInsets.all(_w(16)),
      decoration: detail
          ? null
          : BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(_r(20)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyedSubtree(
            key: const ValueKey('post-header'),
            child: _buildHeader(),
          ),
          if (widget.text.isNotEmpty) ...[
            SizedBox(height: _h(widget.homePresentation ? 20 : 12)),
            _buildText(),
          ],
          if (widget.location != null) ...[
            SizedBox(height: _h(10)),
            _buildLocation(),
          ],
          if (_hasCarousel) ...[
            SizedBox(height: _h(12)),
            _buildCarousel(),
          ] else if (_hasSingleImage) ...[
            SizedBox(height: _h(12)),
            _buildSingleImage(),
          ],
          SizedBox(
            key: const ValueKey('post-content-actions-gap'),
            height: widget.homePresentation ? 20 : _h(12),
          ),
          KeyedSubtree(
            key: const ValueKey('post-actions'),
            child: _buildActions(),
          ),
        ],
      ),
    );
    final onOpen = widget.onOpen;
    if (onOpen == null) return card;
    // Buttons inside win the gesture arena; everything else opens the post.
    return Semantics(
      onTapHint: 'Open post',
      child: GestureDetector(
        key: const ValueKey('post-open'),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: card,
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        UserProfileLink(userId: widget.authorId, child: _buildAvatar()),
        SizedBox(width: _w(10)),
        // Only the text is a profile link; the rest of the row opens the post.
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: UserProfileLink(
              userId: widget.authorId,
              child: Column(
                key: const ValueKey('post-author-text'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    maxLines: widget.responsive ? 2 : null,
                    overflow: widget.responsive ? TextOverflow.ellipsis : null,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: _font(14),
                    ),
                  ),
                  Text(
                    widget.time,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: _font(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.showFollowButton) _authorFollowAction(),
        if (widget.showMoreButton)
          MoreOptionsButton(
            onTap: widget.onMoreTap,
            size: widget.responsive ? _r(38) : AppSizes.w38,
            height: widget.responsive ? _r(38) : AppSizes.h38,
            radius: _r(20),
          ),
      ],
    );
  }

  Widget _buildAvatar() {
    final avatar = widget.avatar;
    if (avatar == null || avatar.isEmpty) {
      return CircleAvatar(
        radius: _r(20),
        backgroundColor: Color(0xFF2A2A2A),
        child: Icon(Icons.person_rounded, color: Colors.white54),
      );
    }
    return CircleAvatar(
      radius: _r(20),
      backgroundImage: _imageProvider(avatar),
    );
  }

  String? _currentUserId() => viewerUserId(
    context,
    fallbackId: widget.currentUserId,
    fallbackSession: widget.currentUserSessionRevision,
  );

  bool _canDisplayFollow() {
    // Keep the existing API for static/legacy cards without author metadata.
    // Every model-backed follow-enabled card supplies the real author ID.
    if (widget.authorId == null) return true;
    final author = normalizeUserId(widget.authorId);
    final viewer = _currentUserId();
    // Unknown identity is not ownership proof, and must not flash a follow CTA.
    return author != null && viewer != null && author != viewer;
  }

  Widget _authorFollowAction() {
    Widget action() => _canDisplayFollow()
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFollowButton(),
              SizedBox(width: _w(8)),
            ],
          )
        : const SizedBox.shrink();
    if (widget.authorId == null) return action();
    final current = context.read<CurrentUserCubit?>();
    return ListenableBuilder(
      listenable: PreferencesManager(),
      builder: (context, _) => current == null
          ? action()
          : BlocBuilder<CurrentUserCubit, CurrentUserState>(
              bloc: current,
              builder: (context, state) => action(),
            ),
    );
  }

  Widget _buildFollowButton() {
    return InkWell(
      onTap: widget.isFollowPending || widget.onFollowTap == null
          ? null
          : () {
              // A retained tap handler can predate an identity/session update.
              if (mounted && _canDisplayFollow()) widget.onFollowTap!();
            },
      overlayColor: widget.neutralFollowButton
          ? const WidgetStatePropertyAll(Colors.white10)
          : null,
      borderRadius: BorderRadius.circular(
        _r(widget.neutralFollowButton ? 30 : 20),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: _w(14), vertical: _h(8)),
        decoration: BoxDecoration(
          color: widget.neutralFollowButton
              ? (widget.isFollowing
                    ? const Color(0xFF262626)
                    : const Color(0xFF303030))
              : (widget.isFollowing
                    ? Colors.transparent
                    : DarkColors.primaryColor),
          border: widget.isFollowing
              ? Border.all(
                  color: widget.neutralFollowButton
                      ? const Color(0xFF444444)
                      : const Color(0xFF3B3B3B),
                )
              : null,
          borderRadius: BorderRadius.circular(
            _r(widget.neutralFollowButton ? 30 : 20),
          ),
        ),
        // Paint Follow's new border without adding inset/size. Following already
        // had a decoration border, so its original layout is retained above.
        foregroundDecoration: widget.neutralFollowButton && !widget.isFollowing
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(_r(30)),
                border: Border.all(color: const Color(0xFF444444)),
              )
            : null,
        child: Text(
          widget.isFollowPending
              ? 'Updating…'
              : widget.isFollowing
              ? 'Following'
              : 'Follow',
          style: TextStyle(
            color: Colors.white,
            fontSize: _font(12),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildText() {
    if (widget.detailPresentation) {
      return Text(
        widget.text,
        style: TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          color: Colors.white,
          fontSize: _font(16),
          height: 1.5,
        ),
      );
    }
    if (widget.homePresentation) {
      return HomePostCaption(
        key: ValueKey(widget.postId),
        postId: widget.postId,
        text: widget.text,
        style: TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          color: Colors.white,
          fontSize: _font(14),
          height: 1.4,
        ),
      );
    }
    final needsTruncation = widget.text.length > 90; // rough 3-line heuristic

    if (!needsTruncation) {
      return Text(
        widget.text,
        style: TextStyle(color: Colors.white, fontSize: _font(14), height: 1.4),
      );
    }

    // An openable card shows the full caption on the Post screen instead.
    if (_isExpanded && widget.onOpen == null) {
      return GestureDetector(
        onTap: () => setState(() => _isExpanded = false),
        child: Text(
          widget.text,
          style: TextStyle(
            color: Colors.white,
            fontSize: _font(14),
            height: 1.4,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onOpen != null
          ? null
          : () => setState(() => _isExpanded = true),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            color: Colors.white,
            fontSize: _font(14),
            height: 1.4,
          ),
          children: [
            TextSpan(text: widget.text),
            TextSpan(
              text: '  read more...',
              style: TextStyle(
                color: DarkColors.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        maxLines: _collapsedMaxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildLocation() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _w(10), vertical: _h(6)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(_r(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_on_outlined,
            color: Colors.white70,
            size: 14,
          ),
          SizedBox(width: _w(4)),
          if (widget.responsive)
            Flexible(
              child: Text(
                widget.location!,
                style: TextStyle(
                  color: DarkColors.whiteColor,
                  fontSize: _font(12),
                ),
              ),
            )
          else
            Text(
              widget.location!,
              style: TextStyle(
                color: DarkColors.whiteColor,
                fontSize: _font(12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_r(16)),
      child: Image(
        image: _imageProvider(widget.image!),
        height: _h(220),
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _imageError(_h(220)),
      ),
    );
  }

  Widget _buildCarousel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_r(16)),
      child: SizedBox(
        height: _h(260),
        child: Stack(
          children: [
            PageView.builder(
              itemCount: widget.images!.length,
              onPageChanged: (i) => setState(() => _imageIndex = i),
              itemBuilder: (context, i) => Image(
                image: _imageProvider(widget.images![i]),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, _, _) => _imageError(_h(260)),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.images!.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _imageIndex ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _imageIndex ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageError(double height) {
    return Container(
      height: height,
      width: double.infinity,
      color: const Color(0xFF1C1C1C),
      child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
    );
  }

  Widget _buildActions() {
    final count = context
        .watch<PostActivityCubit?>()
        ?.state
        .comments[widget.postId];
    final bordered = !widget.detailPresentation;
    final actions = <Widget>[
      _buildLikeAction(),
      ActionIconButton(
        responsive: widget.responsive,
        bordered: bordered,
        iconPath: 'assets/images/interactions/message.svg',
        count: count == null ? widget.comments : formatCount(count),
        onTap: widget.onCommentsTap,
      ),
      Semantics(
        button: true,
        label: 'Share post',
        enabled: widget.onShareTap != null,
        child: ActionIconButton(
          key: const ValueKey('post-share'),
          responsive: widget.responsive,
          bordered: bordered,
          iconPath: 'assets/images/icons/send.svg',
          onTap: widget.onShareTap,
        ),
      ),
    ];
    final save = Semantics(
      button: true,
      toggled: widget.isSaved,
      label: widget.isSaved ? 'Unsave post' : 'Save post',
      enabled: !widget.isSavePending && widget.onSaveTap != null,
      child: Tooltip(
        message: widget.isSaved ? 'Unsave post' : 'Save post',
        child: ActionIconButton(
          key: const ValueKey('post-save'),
          responsive: widget.responsive,
          bordered: false,
          iconPath: widget.isSaved
              ? 'assets/images/interactions/archive 2.svg'
              : 'assets/images/interactions/archive.svg',
          onTap: widget.isSavePending ? null : widget.onSaveTap,
        ),
      ),
    );
    if (widget.responsive) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: _w(8),
              runSpacing: _h(8),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ),
          SizedBox(width: _w(8)),
          save,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        actions[0],
        SizedBox(width: AppSizes.w8),
        actions[1],
        SizedBox(width: AppSizes.w8),
        actions[2],
        const Spacer(),
        save,
      ],
    );
  }
}

/// Like control split in two inside one pill the size of [ActionIconButton]:
/// heart toggles the like, count opens "Liked by".
extension on _PostCardState {
  Widget _buildLikeAction() {
    final responsive = widget.responsive;
    final radius = BorderRadius.circular(
      responsive ? AppSizes.adaptiveRadius(24) : AppSizes.r24,
    );
    final iconSize = responsive ? AppSizes.adaptiveRadius(18) : 18.0;
    final horizontal = responsive ? AppSizes.adaptiveWidth(8) : AppSizes.pw8;
    final vertical = responsive ? AppSizes.adaptiveHeight(6) : AppSizes.ph6;
    // ActionIconButton's icon-to-count gap, shared by the two tap areas.
    final halfGap = (responsive ? AppSizes.adaptiveWidth(6) : 6) / 2;
    final heart = Semantics(
      button: true,
      label: widget.isLiked ? 'Unlike post' : 'Like post',
      toggled: widget.isLiked,
      enabled: !widget.isLikePending && widget.onLikeTap != null,
      child: InkWell(
        key: const ValueKey('post-like'),
        borderRadius: radius,
        onTap: widget.isLikePending ? null : widget.onLikeTap,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            horizontal,
            vertical,
            halfGap,
            vertical,
          ),
          child: SvgPicture.asset(
            widget.isLiked
                ? 'assets/images/interactions/heart.svg'
                : 'assets/images/interactions/heart2.svg',
            width: iconSize,
            height: iconSize,
          ),
        ),
      ),
    );
    final count = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        halfGap,
        vertical,
        horizontal,
        vertical,
      ),
      child: Text(
        widget.detailPresentation
            ? countLabel(widget.likes, 'Like')
            : widget.likes,
        style: TextStyle(
          color: DarkColors.whiteColor,
          fontSize: responsive ? AppSizes.adaptiveFont(13) : 13,
          height: ActionIconButton.countLineHeight,
        ),
      ),
    );
    return Container(
      key: const ValueKey('post-like-pill'),
      decoration: BoxDecoration(
        border: widget.detailPresentation
            ? null
            : Border.all(color: const Color(0xFF2E2E2E)),
        borderRadius: radius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          heart,
          if (widget.onLikesCountTap == null)
            count
          else
            Semantics(
              button: true,
              label: 'View likes',
              child: InkWell(
                key: const ValueKey('post-likes-count'),
                borderRadius: radius,
                onTap: widget.onLikesCountTap,
                child: ExcludeSemantics(child: count),
              ),
            ),
        ],
      ),
    );
  }
}

/// Network URL (from the API) or local asset path.
ImageProvider _imageProvider(String path) {
  if (path.startsWith('http')) return NetworkImage(path);
  return AssetImage(path);
}
