package com.morphlet.controllers

import android.animation.ArgbEvaluator
import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Picture
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.doOnPreDraw
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.findViewTreeLifecycleOwner
import androidx.lifecycle.findViewTreeViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.findViewTreeSavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.facebook.react.R
import com.facebook.react.uimanager.PixelUtil.dpToPx
import com.facebook.react.uimanager.ThemedReactContext
import com.morphlet.animation.MorphletSpring
import com.morphlet.animation.MorphletSpring.Companion.lerp
import com.morphlet.animation.MorphletSpringConfig
import com.morphlet.device.MorphletDisplayCorners
import com.morphlet.enums.MorphletPresentationState
import com.morphlet.protocols.MorphletControllerDelegate
import com.morphlet.utils.MorphletSnapshot
import com.morphlet.views.MorphletTouchRootView
import com.morphlet.views.MorphletWindowView
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MorphletController(private val reactContext: ThemedReactContext) {

  var delegate: MorphletControllerDelegate? = null

  val touchRoot = MorphletTouchRootView(reactContext)

  var cardColor: Int? = null
    set(value) {
      field = value
      applyColors()
    }

  var backdropColor: Int? = null
    set(value) {
      field = value
      applyColors()
    }

  var cornerRadius = DEFAULT_CORNER_RADIUS
    set(value) {
      if (field == value) return
      field = value
      if (!isMorphing) applyCardGeometry(null)
    }

  var cornerSmoothing = DEFAULT_CORNER_SMOOTHING
    set(value) {
      field = value
      applyFrame()
    }

  var bottomOffset = DEFAULT_BOTTOM_OFFSET
    set(value) {
      if (field == value) return
      field = value
      applyCardGeometry(null)
    }

  var backdropOpacity = DEFAULT_BACKDROP_OPACITY
    set(value) {
      field = value
      applyColors()
    }

  var dismissible = true
  var draggable = true
  var fadesOnDrag = true
  var fullScreen = false
  var stacked = false

  var presentSpring: MorphletSpringConfig? = null
  var dismissSpring: MorphletSpringConfig? = null
  var morphSpring: MorphletSpringConfig? = null
  var snapSpring: MorphletSpringConfig? = null

  var originView: View?
    get() = originReference?.get()
    set(value) {
      originReference = value?.let { WeakReference(it) }
    }

  var presentationState = MorphletPresentationState.DISMISSED
    private set

  var keyboardHeight = 0f
    private set

  val windowView: MorphletWindowView?
    get() = window

  internal var dragOffset = 0f
  internal var stackDepth = 0
  internal var didPushStack = false
  internal var isMorphing = false

  internal val resolvedPresentSpring: MorphletSpringConfig
    get() = presentSpring ?: MorphletSpringConfig.fromResponse(0.4f, 0.75f)

  internal val resolvedDismissSpring: MorphletSpringConfig
    get() = dismissSpring ?: MorphletSpringConfig.fromResponse(0.35f, 1f)

  internal val resolvedMorphSpring: MorphletSpringConfig
    get() = morphSpring ?: MorphletSpringConfig.fromResponse(0.5f, 0.86f)

  internal val resolvedSnapSpring: MorphletSpringConfig
    get() = snapSpring ?: MorphletSpringConfig.fromResponse(0.3f, 0.7f)

  private var originReference: WeakReference<View>? = null
  private var dialog: Dialog? = null
  private var window: MorphletWindowView? = null
  private var contentView: View? = null
  private val dragHandler = MorphletDragHandler(this)
  private val keyboardObserver = MorphletKeyboardObserver(this)

  private val frame = RectF()
  private var radius = 0f
  private var fullScreenAmount = 0f
  private var frameSpring: MorphletSpring? = null
  private var cardSpring: MorphletSpring? = null
  private val effectSprings = mutableListOf<MorphletSpring>()

  private var originSnapshot: Picture? = null
  private var originColor = Color.TRANSPARENT
  private var originRadius = 0f
  private var morphedOriginReference: WeakReference<View>? = null
  private var originAlpha = 1f

  fun setContentView(view: View?) {
    if (contentView === view) return
    contentView?.let { touchRoot.removeView(it) }
    contentView = view
    view?.let { touchRoot.addView(it) }
  }

  fun present(activity: Activity) {
    if (presentationState != MorphletPresentationState.DISMISSED) return
    presentationState = MorphletPresentationState.PRESENTING

    val windowView = createWindow(activity)
    dragOffset = 0f
    keyboardHeight = 0f
    windowView.backdrop.alpha = 0f
    windowView.card.alpha = 1f
    windowView.card.translationY = OFFSCREEN_SENTINEL

    delegate?.controllerWillPresent()
    MorphletStack.didPresent(this)

    windowView.doOnPreDraw { beginPresentation() }
  }

  fun dismiss(animated: Boolean) {
    dismiss(velocity = 0f, interactive = false, animated = animated)
  }

  fun contentSizeDidChange(spring: MorphletSpringConfig?) {
    applyCardGeometry(spring)
  }

  fun revealFocusedInput() {
    if (keyboardHeight <= 0f) return
    val focused = contentView?.findFocus() ?: return
    focused.post { focused.requestRectangleOnScreen(Rect(0, 0, focused.width, focused.height), false) }
  }

  internal fun dismiss(velocity: Float, interactive: Boolean, animated: Boolean) {
    if (presentationState == MorphletPresentationState.DISMISSED ||
      presentationState == MorphletPresentationState.DISMISSING
    ) {
      return
    }
    presentationState = MorphletPresentationState.DISMISSING
    cancelAnimations()
    isMorphing = false

    delegate?.controllerWillDismiss(interactive)
    hideKeyboard()
    dialog?.window?.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)

    val origin = morphableOriginView()
    val card = window?.card
    val foldsIntoOrigin = animated && origin != null && originSnapshot != null && card != null &&
      abs(card.translationY) < 1f
    MorphletStack.restore(this, if (foldsIntoOrigin) resolvedMorphSpring.withoutBounce() else resolvedDismissSpring)

    when {
      !animated || card == null -> finishDismissing()
      foldsIntoOrigin -> morphOut(origin!!)
      else -> slideOut(velocity)
    }
  }

  internal fun canDrag(): Boolean =
    draggable && !isMorphing &&
      (presentationState == MorphletPresentationState.PRESENTED ||
        presentationState == MorphletPresentationState.PRESENTING)

  internal fun beginDrag() {
    cardSpring?.cancel()
    cardSpring = null
    finishPresentingIfNeeded()
    dragOffset = window?.card?.translationY ?: 0f
  }

  internal fun dragBy(delta: Float) {
    dragOffset += delta
    applyDragOffset()
  }

  internal fun endDrag(velocity: Float, completed: Boolean) {
    if (dragOffset == 0f || presentationState != MorphletPresentationState.PRESENTED) return
    val offset = displayOffset()
    val dismissVelocity = DISMISS_VELOCITY.dpToPx()
    val shouldDismiss = dismissible && completed && offset > 0f &&
      ((offset > DISMISS_THRESHOLD.dpToPx() && velocity > -RETURN_VELOCITY.dpToPx()) || velocity > dismissVelocity)
    if (shouldDismiss) {
      dismiss(max(0f, velocity), interactive = true, animated = true)
    } else {
      snapBack(velocity)
    }
  }

  internal fun keyboardDidChange(height: Float) {
    if (abs(height - keyboardHeight) < 0.5f) return
    keyboardHeight = height
    applyCardGeometry(resolvedPresentSpring)
    delegate?.controllerInsetsDidChange()
  }

  internal fun insetsDidChange() {
    delegate?.controllerInsetsDidChange()
  }

  internal fun applyStackDepth(depth: Int, spring: MorphletSpringConfig) {
    val windowView = window ?: return
    if (stackDepth == depth) return
    stackDepth = depth

    val layer = windowView.stackLayer
    val backdrop = windowView.backdrop
    val scale = max(STACK_MINIMUM_SCALE, 1f - STACK_SCALE_STEP * depth)
    val lift = -STACK_LIFT_STEP.dpToPx() * depth
    val backdropAlpha = if (depth > 0) 0f else backdropOpacity
    layer.pivotX = layer.width / 2f
    layer.pivotY = frame.top

    val fromScale = layer.scaleX
    val fromLift = layer.translationY
    val fromBackdrop = backdrop.alpha
    trackEffect(
      MorphletSpring.start(spring, onUpdate = { progress ->
        val currentScale = lerp(fromScale, scale, progress)
        layer.scaleX = currentScale
        layer.scaleY = currentScale
        layer.translationY = lerp(fromLift, lift, progress)
        backdrop.alpha = lerp(fromBackdrop, backdropAlpha, progress).coerceIn(0f, 1f)
      })
    )
  }

  private fun createWindow(activity: Activity): MorphletWindowView {
    val windowView = MorphletWindowView(activity)
    window = windowView
    windowView.card.content = touchRoot
    windowView.card.gestureHandler = dragHandler
    windowView.stackLayer.onLayoutChildren = { layoutCard() }
    windowView.backdrop.setOnClickListener {
      if (dismissible) dismiss(velocity = 0f, interactive = true, animated = true)
    }
    keyboardObserver.observe(windowView)
    applyColors()

    val newDialog = Dialog(activity, R.style.Theme_FullScreenDialog)
    dialog = newDialog
    shareViewTreeOwners(activity, newDialog)
    newDialog.setContentView(windowView)
    newDialog.setOnKeyListener { _, keyCode, event ->
      val isBack = keyCode == KeyEvent.KEYCODE_BACK || keyCode == KeyEvent.KEYCODE_ESCAPE
      if (isBack && event.action == KeyEvent.ACTION_UP && dismissible) {
        dismiss(velocity = 0f, interactive = true, animated = true)
      }
      isBack
    }
    configureWindow(newDialog, activity)
    newDialog.show()
    return windowView
  }

  private fun shareViewTreeOwners(activity: Activity, dialog: Dialog) {
    val decorView = dialog.window?.decorView ?: return
    val activityView = activity.window.decorView
    (activityView.findViewTreeLifecycleOwner() ?: activity as? LifecycleOwner)
      ?.let { decorView.setViewTreeLifecycleOwner(it) }
    (activityView.findViewTreeSavedStateRegistryOwner() ?: activity as? SavedStateRegistryOwner)
      ?.let { decorView.setViewTreeSavedStateRegistryOwner(it) }
    (activityView.findViewTreeViewModelStoreOwner() ?: activity as? ViewModelStoreOwner)
      ?.let { decorView.setViewTreeViewModelStoreOwner(it) }
  }

  @Suppress("DEPRECATION")
  private fun configureWindow(dialog: Dialog, activity: Activity) {
    val dialogWindow = dialog.window ?: return
    dialogWindow.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    dialogWindow.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
    dialogWindow.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
    dialogWindow.setWindowAnimations(0)
    dialogWindow.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    WindowCompat.setDecorFitsSystemWindows(dialogWindow, false)
    dialogWindow.statusBarColor = Color.TRANSPARENT
    dialogWindow.navigationBarColor = Color.TRANSPARENT
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      dialogWindow.isNavigationBarContrastEnforced = false
      dialogWindow.isStatusBarContrastEnforced = false
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      dialogWindow.attributes.layoutInDisplayCutoutMode =
        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
    }

    val activityAppearance = WindowInsetsControllerCompat(activity.window, activity.window.decorView)
    val dialogAppearance = WindowInsetsControllerCompat(dialogWindow, dialogWindow.decorView)
    dialogAppearance.isAppearanceLightStatusBars = activityAppearance.isAppearanceLightStatusBars
    dialogAppearance.isAppearanceLightNavigationBars = activityAppearance.isAppearanceLightNavigationBars
  }

  private fun beginPresentation() {
    if (presentationState != MorphletPresentationState.PRESENTING) return
    val origin = morphableOriginView()

    if (stacked) {
      MorphletStack.push(this, if (origin != null) resolvedMorphSpring else resolvedPresentSpring)
    }

    if (origin != null) {
      prepareMorph(origin)
      morphIn()
    } else {
      slideIn()
    }
  }

  private fun slideIn() {
    val windowView = window ?: return
    setGeometry(targetFrame(), targetRadius(), targetFullScreenAmount())
    val card = windowView.card
    val backdrop = windowView.backdrop
    val from = offscreenOffset()
    card.translationY = from

    cardSpring = MorphletSpring.start(
      resolvedPresentSpring,
      onUpdate = { progress ->
        card.translationY = lerp(from, 0f, progress)
        backdrop.alpha = lerp(0f, backdropOpacity, progress).coerceIn(0f, 1f)
      },
      onEnd = { finished -> if (finished) finishPresentingIfNeeded() },
    )
  }

  private fun prepareMorph(origin: View) {
    val windowView = window ?: return
    isMorphing = true
    morphedOriginReference = WeakReference(origin)
    originAlpha = if (origin.alpha > 0.01f) origin.alpha else 1f

    val originFrame = frameOf(origin)
    originColor = MorphletSnapshot.visibleBackgroundColor(origin, resolvedCardColor())
    originRadius = min(MorphletSnapshot.cornerRadius(origin), min(originFrame.width(), originFrame.height()) / 2)
    originSnapshot = MorphletSnapshot.recordContents(origin)

    val card = windowView.card
    card.translationY = 0f
    card.snapshot = originSnapshot
    card.snapshotAlpha = 1f
    card.coverColor = originColor
    card.coverAlpha = 1f
    setGeometry(originFrame, originRadius, 0f)
    origin.alpha = 0f
  }

  private fun morphIn() {
    val windowView = window ?: return
    val card = windowView.card
    val backdrop = windowView.backdrop
    val cardColor = resolvedCardColor()
    val colors = ArgbEvaluator()

    animateGeometry(targetFrame(), targetRadius(), targetFullScreenAmount(), resolvedMorphSpring) { finished ->
      if (!finished) return@animateGeometry
      isMorphing = false
      card.snapshot = null
      applyFrame()
      finishPresentingIfNeeded()
    }
    trackEffect(
      MorphletSpring.start(resolvedMorphSpring, onUpdate = { progress ->
        backdrop.alpha = lerp(0f, backdropOpacity, progress).coerceIn(0f, 1f)
      })
    )
    trackEffect(
      MorphletSpring.start(MorphletSpringConfig.fromResponse(0.18f, 1f), onUpdate = { progress ->
        card.snapshotAlpha = 1f - progress
      })
    )
    trackEffect(
      MorphletSpring.start(MorphletSpringConfig.fromResponse(0.32f, 1f), delayMillis = 40, onUpdate = { progress ->
        card.coverColor = colors.evaluate(progress.coerceIn(0f, 1f), originColor, cardColor) as Int
        card.coverAlpha = 1f - progress
      })
    )
  }

  private fun morphOut(origin: View) {
    val windowView = window ?: return
    isMorphing = true
    val card = windowView.card
    val backdrop = windowView.backdrop
    val cardColor = resolvedCardColor()
    val colors = ArgbEvaluator()
    val fromBackdrop = backdrop.alpha

    // Re-capture the trigger: its contents may have changed while the tray was open. Then hide it
    // again, since a React re-render while open can have restored its opacity.
    MorphletSnapshot.recordContents(origin)?.let { originSnapshot = it }
    origin.alpha = 0f
    card.translationY = 0f
    card.alpha = 1f
    card.snapshot = originSnapshot
    card.snapshotAlpha = 0f
    card.coverColor = cardColor
    card.coverAlpha = 0f

    animateGeometry(frameOf(origin), originRadius, 0f, resolvedMorphSpring.withoutBounce()) {
      handOffToOrigin(origin)
    }
    trackEffect(
      MorphletSpring.start(resolvedMorphSpring.withoutBounce(), onUpdate = { progress ->
        backdrop.alpha = lerp(fromBackdrop, 0f, progress).coerceIn(0f, 1f)
      })
    )
    trackEffect(
      MorphletSpring.start(MorphletSpringConfig.fromResponse(0.22f, 1f), onUpdate = { progress ->
        card.coverColor = colors.evaluate(progress.coerceIn(0f, 1f), cardColor, originColor) as Int
        card.coverAlpha = progress
      })
    )
    trackEffect(
      MorphletSpring.start(MorphletSpringConfig.fromResponse(0.25f, 1f), delayMillis = 100, onUpdate = { progress ->
        card.snapshotAlpha = progress
      })
    )
  }

  private fun handOffToOrigin(origin: View) {
    if (presentationState != MorphletPresentationState.DISMISSING) return
    origin.alpha = originAlpha
    val card = window?.card ?: return finishDismissing()
    cardSpring = MorphletSpring.start(
      MorphletSpringConfig.fromResponse(0.2f, 1f),
      onUpdate = { progress -> card.alpha = 1f - progress.coerceIn(0f, 1f) },
      onEnd = { finishDismissing() },
    )
  }

  private fun slideOut(velocity: Float) {
    val windowView = window ?: return
    val card = windowView.card
    val backdrop = windowView.backdrop
    val from = card.translationY
    val to = offscreenOffset()
    val fromBackdrop = backdrop.alpha
    val hiddenOrigin = morphedOriginReference?.get()
    val distance = max(1f, to - from)

    cardSpring = MorphletSpring.start(
      resolvedDismissSpring,
      velocity = velocity / distance,
      onUpdate = { progress ->
        card.translationY = lerp(from, to, progress)
        backdrop.alpha = lerp(fromBackdrop, 0f, progress).coerceIn(0f, 1f)
        hiddenOrigin?.alpha = originAlpha * progress.coerceIn(0f, 1f)
      },
      onEnd = { finishDismissing() },
    )
  }

  private fun snapBack(velocity: Float) {
    val windowView = window ?: return
    val card = windowView.card
    val backdrop = windowView.backdrop
    val from = displayOffset()
    val fromAlpha = card.alpha
    val fromBackdrop = backdrop.alpha
    dragOffset = 0f
    val relativeVelocity = if (abs(from) > 1f) -velocity / from else 0f

    cardSpring = MorphletSpring.start(
      resolvedSnapSpring,
      velocity = relativeVelocity,
      onUpdate = { progress ->
        card.translationY = lerp(from, 0f, progress)
        card.alpha = lerp(fromAlpha, 1f, progress)
        backdrop.alpha = lerp(fromBackdrop, backdropOpacity, progress).coerceIn(0f, 1f)
      },
    )
  }

  private fun finishPresentingIfNeeded() {
    if (presentationState != MorphletPresentationState.PRESENTING) return
    presentationState = MorphletPresentationState.PRESENTED
    delegate?.controllerDidPresent()
  }

  private fun finishDismissing() {
    if (presentationState != MorphletPresentationState.DISMISSING) return
    cancelAnimations()
    MorphletStack.remove(this)

    val windowView = window
    windowView?.card?.content = null
    touchRoot.translationX = 0f
    touchRoot.translationY = 0f
    dialog?.dismiss()
    dialog = null
    window = null

    morphedOriginReference?.get()?.alpha = originAlpha
    morphedOriginReference = null
    originSnapshot = null
    isMorphing = false
    dragOffset = 0f
    keyboardHeight = 0f
    stackDepth = 0
    didPushStack = false
    presentationState = MorphletPresentationState.DISMISSED
    delegate?.controllerDidDismiss()
  }

  private fun cancelAnimations() {
    frameSpring?.cancel()
    frameSpring = null
    cardSpring?.cancel()
    cardSpring = null
    effectSprings.forEach { it.cancel() }
    effectSprings.clear()
  }

  private fun trackEffect(spring: MorphletSpring) {
    effectSprings.removeAll { !it.isRunning }
    effectSprings.add(spring)
  }

  private fun layoutCard() {
    if (frameSpring?.isRunning == true || isMorphing ||
      presentationState == MorphletPresentationState.DISMISSING
    ) {
      applyFrame()
      return
    }
    setGeometry(targetFrame(), targetRadius(), targetFullScreenAmount())
  }

  private fun applyCardGeometry(spring: MorphletSpringConfig?) {
    if (window == null || isMorphing || presentationState == MorphletPresentationState.DISMISSING) return
    if (spring == null || presentationState == MorphletPresentationState.DISMISSED) {
      setGeometry(targetFrame(), targetRadius(), targetFullScreenAmount())
    } else {
      animateGeometry(targetFrame(), targetRadius(), targetFullScreenAmount(), spring, null)
    }
  }

  private fun setGeometry(target: RectF, targetRadius: Float, targetFullScreen: Float) {
    frameSpring?.cancel()
    frameSpring = null
    frame.set(target)
    radius = targetRadius
    fullScreenAmount = targetFullScreen
    applyFrame()
  }

  private fun animateGeometry(
    target: RectF,
    targetRadius: Float,
    targetFullScreen: Float,
    spring: MorphletSpringConfig,
    onEnd: ((Boolean) -> Unit)?,
  ) {
    frameSpring?.cancel()
    val from = RectF(frame)
    val fromRadius = radius
    val fromFullScreen = fullScreenAmount
    frameSpring = MorphletSpring.start(
      spring,
      onUpdate = { progress ->
        frame.set(
          lerp(from.left, target.left, progress),
          lerp(from.top, target.top, progress),
          lerp(from.right, target.right, progress),
          lerp(from.bottom, target.bottom, progress),
        )
        radius = max(0f, lerp(fromRadius, targetRadius, progress))
        fullScreenAmount = lerp(fromFullScreen, targetFullScreen, progress)
        applyFrame()
      },
      onEnd = onEnd,
    )
  }

  private fun applyFrame() {
    val card = window?.card ?: return
    val content = contentView
    card.contentWidth = content?.width ?: 0
    card.contentHeight = content?.height ?: 0
    card.cornerRadius = radius
    card.cornerSmoothing = cornerSmoothing * (1f - fullScreenAmount.coerceIn(0f, 1f))
    card.layout(
      frame.left.roundToInt(),
      frame.top.roundToInt(),
      frame.right.roundToInt(),
      frame.bottom.roundToInt(),
    )

    if (isMorphing) {
      touchRoot.translationX = (frame.width() - card.contentWidth) / 2f
      touchRoot.translationY = frame.height() - card.contentHeight
    } else {
      touchRoot.translationX = 0f
      touchRoot.translationY = 0f
    }
  }

  private fun applyDragOffset() {
    val windowView = window ?: return
    val offset = displayOffset()
    val down = max(0f, offset)
    windowView.card.translationY = offset
    windowView.card.alpha = if (dismissible && fadesOnDrag) max(0f, 1f - down / FADE_DISTANCE.dpToPx()) else 1f
    val progress = min(1f, down / max(1f, offscreenOffset()))
    windowView.backdrop.alpha = backdropOpacity * (1f - progress)
  }

  private fun displayOffset(): Float =
    when {
      dragOffset < 0f -> -rubberBand(-dragOffset, UPWARD_RESISTANCE.dpToPx())
      !dismissible -> rubberBand(dragOffset, DOWNWARD_RESISTANCE.dpToPx())
      else -> dragOffset
    }

  private fun targetFrame(): RectF {
    val windowView = window ?: return RectF()
    val width = windowView.width.toFloat()
    val height = windowView.height.toFloat()
    val contentWidth = contentView?.width?.toFloat()?.takeIf { it > 0f } ?: max(0f, width - 32f.dpToPx())
    val contentHeight = contentView?.height?.toFloat() ?: 0f
    val inset = if (fullScreen) 0f else bottomOffset.dpToPx()
    val bottom = height - inset - keyboardHeight
    val left = (width - contentWidth) / 2f
    return RectF(left, bottom - contentHeight, left + contentWidth, bottom)
  }

  private fun targetRadius(): Float {
    val windowView = window ?: return cornerRadius.dpToPx()
    return if (fullScreen) MorphletDisplayCorners.radius(windowView) else cornerRadius.dpToPx()
  }

  private fun targetFullScreenAmount(): Float = if (fullScreen) 1f else 0f

  private fun offscreenOffset(): Float {
    val height = window?.height?.toFloat() ?: return 0f
    return max(0f, height - frame.top) + 8f.dpToPx()
  }

  private fun morphableOriginView(): View? {
    val origin = originView ?: return null
    return if (origin.isAttachedToWindow && origin.width > 0 && origin.height > 0) origin else null
  }

  private fun frameOf(view: View): RectF {
    val windowView = window ?: return RectF()
    val root = view.rootView as? ViewGroup
    val bounds = Rect(0, 0, view.width, view.height)
    val rootOnScreen = IntArray(2)
    val windowOnScreen = IntArray(2)
    if (root != null && root !== view) {
      root.offsetDescendantRectToMyCoords(view, bounds)
      root.getLocationOnScreen(rootOnScreen)
    } else {
      view.getLocationOnScreen(rootOnScreen)
    }
    windowView.getLocationOnScreen(windowOnScreen)
    val dx = (rootOnScreen[0] - windowOnScreen[0]).toFloat()
    val dy = (rootOnScreen[1] - windowOnScreen[1]).toFloat()
    return RectF(bounds.left + dx, bounds.top + dy, bounds.right + dx, bounds.bottom + dy)
  }

  private fun applyColors() {
    val windowView = window ?: return
    if (!isMorphing) {
      windowView.card.cardColor = resolvedCardColor()
    }
    windowView.backdrop.setBackgroundColor(backdropColor ?: Color.BLACK)
    if (presentationState == MorphletPresentationState.PRESENTED && dragOffset == 0f &&
      cardSpring?.isRunning != true && stackDepth == 0
    ) {
      windowView.backdrop.alpha = backdropOpacity
    }
  }

  private fun resolvedCardColor(): Int {
    cardColor?.let { return it }
    val nightMode = reactContext.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    return if (nightMode == Configuration.UI_MODE_NIGHT_YES) DARK_CARD_COLOR else Color.WHITE
  }

  private fun hideKeyboard() {
    val windowView = window ?: return
    val focused = windowView.findFocus() ?: return
    val inputMethodManager = windowView.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
    inputMethodManager?.hideSoftInputFromWindow(focused.windowToken, 0)
    focused.clearFocus()
  }

  private fun rubberBand(offset: Float, dimension: Float): Float =
    (1f - (1f / ((offset * 0.55f / dimension) + 1f))) * dimension

  companion object {
    const val DEFAULT_CORNER_RADIUS = 32f
    const val DEFAULT_CORNER_SMOOTHING = 0.6f
    const val DEFAULT_BOTTOM_OFFSET = 16f
    const val DEFAULT_BACKDROP_OPACITY = 0.3f

    private const val OFFSCREEN_SENTINEL = 100000f
    private const val DISMISS_THRESHOLD = 120f
    private const val FADE_DISTANCE = DISMISS_THRESHOLD * 2.5f
    private const val DISMISS_VELOCITY = 1000f
    private const val RETURN_VELOCITY = 300f
    private const val UPWARD_RESISTANCE = 60f
    private const val DOWNWARD_RESISTANCE = 180f
    private const val STACK_SCALE_STEP = 0.06f
    private const val STACK_MINIMUM_SCALE = 0.7f
    private const val STACK_LIFT_STEP = 14f
    private val DARK_CARD_COLOR = Color.rgb(28, 28, 30)
  }
}
