extends Node
## Rewarded ads (Google AdMob, addons/admob; phones only), the "+1 life" offer when the bubble is
## out of lives. At start() it asks for consent where the law wants it (EU / UK: Google's consent
## form), starts AdMob and preloads one ad; after each one it loads the next.
## `show_rewarded()` plays the loaded ad and says whether the player earned the reward.
## Same setup as 99 cuts (scripts/ads.gd there), which found the pitfalls noted below.

enum Result { NO_AD, EARNED, SKIPPED }

## The rewarded ad units ("Extra life") of the apps "99 jumps" in the AdMob account behind
## buurtfix@gmail.com, used by release builds. Debug builds use Google's TEST units, so developing
## never counts as real impressions. The app ids (admob/general/android|ios/app_id) are in
## project.godot.
const REWARDED_ANDROID := "ca-app-pub-3037344212716368/5003389475"
const REWARDED_IOS := "ca-app-pub-3037344212716368/7931348873"
const TEST_REWARDED_ANDROID := "ca-app-pub-3940256099942544/5224354917"
const TEST_REWARDED_IOS := "ca-app-pub-3940256099942544/1712485313"
## After a failed load, wait this long before asking for another ad.
const RETRY_SECONDS := 30.0
## Google's consent check sometimes never answers on iOS. After this long the game goes on
## without it: ads start unless consent is known to be needed.
const CONSENT_TIMEOUT := 12.0

signal _closed

var _ad: RewardedAd = null
var _loading := false
var _earned := false
var _started := false
var _ads_started := false
var _consent_answered := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Ads exist only in the phone builds (the native plugin); desktop runs show the stand-in.
static func supported() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


# The AdMob scripts keep our callbacks in static vars for the whole run; on quit Godot clears
# those after freeing this script, and a lambda that uses self then locks a destroyed mutex
# (SIGABRT at every iOS quit in 99 cuts). Drop them while this script is still alive.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or not _started:
		return
	MobileAds._current_on_initialization_complete_listener = null
	MobileAds._current_on_ad_inspector_closed_listener = null
	UserMessagingPlatform.consent_information._on_consent_info_updated_success_callback = null
	UserMessagingPlatform.consent_information._on_consent_info_updated_failure_callback = null
	UserMessagingPlatform.active_consent_form = null
	UserMessagingPlatform._on_consent_form_load_success_listener_callback = null
	UserMessagingPlatform._on_consent_form_load_failure_listener_callback = null
	UserMessagingPlatform._on_privacy_options_form_dismissed_callback = null
	_ad = null


## Starts consent + AdMob. Called a few seconds after launch, once the intro is over: the native
## SDK start blocks the main thread for a moment on a phone.
func start() -> void:
	if _started or not supported():
		return
	_started = true
	_ask_consent()


## Whether an ad could be shown right now.
func is_ready() -> bool:
	return _ad != null


## Plays the loaded ad. NO_AD at once when none is ready (no network, no fill), EARNED when the
## player watched it, SKIPPED when it was closed early.
func show_rewarded() -> Result:
	if _ad == null:
		_load()  # for next time
		return Result.NO_AD
	var ad := _ad
	_ad = null
	_earned = false
	var callbacks := FullScreenContentCallback.new()
	callbacks.on_ad_dismissed_full_screen_content = func() -> void: _closed.emit()
	callbacks.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void: _closed.emit()
	ad.full_screen_content_callback = callbacks
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem) -> void: _earned = true
	ad.show(listener)
	await _closed
	ad.destroy()
	_load()
	return Result.EARNED if _earned else Result.SKIPPED


## Whether the player must be able to reopen the consent form (EU / UK): Settings then shows
## "Privacy options".
func privacy_options_required() -> bool:
	if not _started:
		return false
	var status := UserMessagingPlatform.consent_information.get_privacy_options_requirement_status()
	return status == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options() -> void:
	UserMessagingPlatform.show_privacy_options_form(func(_error: FormError) -> void: pass)


func _ask_consent() -> void:
	var info := UserMessagingPlatform.consent_information
	get_tree().create_timer(CONSENT_TIMEOUT, true).timeout.connect(_on_consent_timeout)
	info.update(ConsentRequestParameters.new(),
		func() -> void:
			_consent_answered = true
			# Google's form, only where it is required (EU / UK) and not answered yet.
			if info.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED \
					and info.get_is_consent_form_available():
				UserMessagingPlatform.load_consent_form(
					func(form: ConsentForm) -> void:
						form.show(func(_error: FormError) -> void: _start()),
					func(_error: FormError) -> void: _start())
			else:
				_start(),
		func(_error: FormError) -> void:
			_consent_answered = true
			_start())


func _on_consent_timeout() -> void:
	if _consent_answered or _ads_started:
		return
	if UserMessagingPlatform.consent_information.get_consent_status() != ConsentInformation.ConsentStatus.REQUIRED:
		_start()


func _start() -> void:
	if _ads_started:
		return
	_ads_started = true
	var on_init := OnInitializationCompleteListener.new()
	on_init.on_initialization_complete = func(_status: InitializationStatus) -> void: _load()
	MobileAds.initialize(on_init)


func _load() -> void:
	if not _ads_started or _loading or _ad != null:
		return
	_loading = true
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_loading = false
		_ad = ad
	callback.on_ad_failed_to_load = func(_error: LoadAdError) -> void:
		_loading = false
		get_tree().create_timer(RETRY_SECONDS, true).timeout.connect(_load)
	var ios := OS.has_feature("ios")
	var unit: String
	if OS.is_debug_build():
		unit = TEST_REWARDED_IOS if ios else TEST_REWARDED_ANDROID
	else:
		unit = REWARDED_IOS if ios else REWARDED_ANDROID
	RewardedAdLoader.new().load(unit, AdRequest.new(), callback)
