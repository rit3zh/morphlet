package com.morphlet.components

import android.annotation.SuppressLint
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.facebook.react.bridge.Arguments
import com.facebook.react.uimanager.PixelUtil.pxToDp
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.common.UIManagerType
import com.facebook.react.uimanager.events.EventDispatcher
import com.morphlet.animation.MorphletSpringConfig
import com.morphlet.controllers.MorphletController
import com.morphlet.enums.MorphletPresentationState
import com.morphlet.events.MorphletEvent
import com.morphlet.events.MorphletEventName
import com.morphlet.protocols.MorphletContainerViewDelegate
import com.morphlet.protocols.MorphletControllerDelegate

@SuppressLint("ViewConstructor")
class MorphletHostView(private val reactContext: ThemedReactContext) :
  ViewGroup(reactContext),
  MorphletControllerDelegate,
  MorphletContainerViewDelegate {

  val controller = MorphletController(reactContext).also { it.delegate = this }

  var eventDispatcher: EventDispatcher? = null
    set(value) {
      field = value
      controller.touchRoot.eventDispatcher = value
    }

  var duration = 0.25f
  var layoutSpring: MorphletSpringConfig? = null
  var originTag = NO_ORIGIN_TAG

  var content: MorphletContainerView? = null
    private set

  private var isOpen = false
  private var wantsPresent = false
  private var isPresentScheduled = false
  private var isDismissScheduled = false
  private var reportedInsets: DoubleArray? = null
  private val layoutListener = ViewTreeObserver.OnGlobalLayoutListener { emitInsetsIfNeeded() }

  init {
    visibility = View.GONE
  }

  override fun setId(id: Int) {
    super.setId(id)
    controller.touchRoot.id = id
  }

  override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) = Unit

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    rootView.viewTreeObserver.addOnGlobalLayoutListener(layoutListener)
    emitInsetsIfNeeded()
    if (wantsPresent) schedulePresent()
  }

  override fun onDetachedFromWindow() {
    rootView.viewTreeObserver.removeOnGlobalLayoutListener(layoutListener)
    super.onDetachedFromWindow()
  }

  fun setOpen(open: Boolean) {
    if (open == isOpen) return
    isOpen = open
    if (open) {
      wantsPresent = true
      schedulePresent()
    } else {
      wantsPresent = false
      scheduleDismiss()
    }
  }

  fun attachContent(view: MorphletContainerView) {
    content = view
    view.delegate = this
    controller.setContentView(view)
    if (wantsPresent) schedulePresent()
  }

  fun detachContent() {
    val view = content ?: return
    if (controller.presentationState != MorphletPresentationState.DISMISSED) {
      controller.dismiss(animated = false)
    }
    view.delegate = null
    controller.setContentView(null)
    content = null
  }

  fun drop() {
    controller.delegate = null
    controller.dismiss(animated = false)
  }

  private fun scheduleDismiss() {
    if (isDismissScheduled) return
    isDismissScheduled = true
    post {
      isDismissScheduled = false
      if (isOpen) return@post
      controller.originView = resolveOrigin()
      controller.dismiss(animated = true)
    }
  }

  private fun schedulePresent() {
    if (isPresentScheduled) return
    isPresentScheduled = true
    post {
      isPresentScheduled = false
      presentIfNeeded()
    }
  }

  private fun presentIfNeeded() {
    val activity = reactContext.currentActivity ?: return
    if (!wantsPresent || !isOpen || content == null || !isAttachedToWindow ||
      controller.presentationState != MorphletPresentationState.DISMISSED
    ) {
      return
    }
    wantsPresent = false
    controller.originView = resolveOrigin()
    controller.present(activity)
    emitInsetsIfNeeded()
  }

  private fun resolveOrigin(): View? {
    if (originTag <= 0) return null
    val uiManager = UIManagerHelper.getUIManager(reactContext, UIManagerType.FABRIC) ?: return null
    return try {
      uiManager.resolveView(originTag)
    } catch (error: RuntimeException) {
      null
    }
  }

  private fun emitInsetsIfNeeded() {
    val source = controller.windowView ?: rootView
    val insets = ViewCompat.getRootWindowInsets(source) ?: return
    val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
    val values =
      doubleArrayOf(
        bars.top.pxToDp().toDouble(),
        insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom.pxToDp().toDouble(),
        controller.keyboardHeight.pxToDp().toDouble(),
        source.width.pxToDp().toDouble(),
        source.height.pxToDp().toDouble(),
      )
    if (reportedInsets?.contentEquals(values) == true) return
    reportedInsets = values

    val data = Arguments.createMap().apply {
      putDouble("top", values[0])
      putDouble("bottom", values[1])
      putDouble("keyboard", values[2])
      putDouble("width", values[3])
      putDouble("height", values[4])
    }
    dispatch(MorphletEventName.INSETS_CHANGE, data)
  }

  private fun dispatch(name: String, data: com.facebook.react.bridge.WritableMap? = null) {
    val dispatcher = eventDispatcher ?: return
    dispatcher.dispatchEvent(MorphletEvent(UIManagerHelper.getSurfaceId(this), id, name, data))
  }

  override fun controllerWillPresent() = dispatch(MorphletEventName.WILL_PRESENT)

  override fun controllerDidPresent() = dispatch(MorphletEventName.DID_PRESENT)

  override fun controllerWillDismiss(interactive: Boolean) = dispatch(MorphletEventName.WILL_DISMISS)

  override fun controllerDidDismiss() {
    dispatch(MorphletEventName.DID_DISMISS)
    if (wantsPresent && isOpen) schedulePresent()
  }

  override fun controllerInsetsDidChange() = emitInsetsIfNeeded()

  override fun containerShouldAnimateLayout(): Boolean =
    controller.presentationState == MorphletPresentationState.PRESENTING ||
      controller.presentationState == MorphletPresentationState.PRESENTED

  override fun containerLayoutSpring(): MorphletSpringConfig =
    layoutSpring ?: MorphletSpringConfig.fromResponse(duration * 1.2f, 0.8f)

  override fun containerLayoutDidChange(animated: Boolean) {
    controller.contentSizeDidChange(if (animated) containerLayoutSpring() else null)
    controller.revealFocusedInput()
  }

  companion object {
    const val NO_ORIGIN_TAG = -1
  }
}
