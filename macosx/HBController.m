/* $Id: Controller.mm,v 1.79 2005/11/04 19:41:32 titer Exp $

   This file is part of the HandBrake source code.
   Homepage: <http://handbrake.fr/>.
   It may be used under the terms of the GNU General Public License. */

#import "HBController.h"
#import "HBAppDelegate.h"
#import "HBFocusRingView.h"
#import "HBToolbarBadgedItem.h"
#import "HBQueueController.h"
#import "HBTitleSelectionController.h"
#import "NSWindow+HBAdditions.h"

#import "HBQueue.h"
#import "HBQueueWorker.h"

#import "HBPresetsMenuBuilder.h"

#import "HBSummaryViewController.h"
#import "HBPictureViewController.h"
#import "HBFiltersViewController.h"
#import "HBVideoController.h"
#import "HBAudioController.h"
#import "HBSubtitlesController.h"
#import "HBChapterTitlesController.h"

#import "HBPreviewController.h"
#import "HBPreviewGenerator.h"

#import "HBPresetsViewController.h"
#import "HBAddPresetController.h"
#import "HBRenamePresetController.h"

#import "HBAutoNamer.h"
#import "HBJob+HBAdditions.h"
#import "HBAttributedStringAdditions.h"

#import "HBPreferencesKeys.h"

static void *HBControllerScanCoreContext = &HBControllerScanCoreContext;
static void *HBControllerLogLevelContext = &HBControllerLogLevelContext;

@interface HBController () <HBPresetsViewControllerDelegate, HBTitleSelectionDelegate, NSMenuItemValidation, NSDraggingDestination, NSPopoverDelegate>
{
    IBOutlet NSTabView *fMainTabView;

    // Picture controller
    HBPictureViewController * fPictureViewController;
    IBOutlet NSTabViewItem  * fPictureTab;

    // Filters controller
    HBFiltersViewController * fFiltersViewController;
    IBOutlet NSTabViewItem  * fFiltersTab;

    // Video view controller
    HBVideoController       * fVideoController;
    IBOutlet NSTabViewItem  * fVideoTab;

    // Subtitles view controller
    HBSubtitlesController   * fSubtitlesViewController;
    IBOutlet NSTabViewItem  * fSubtitlesTab;

    // Audio view controller
    HBAudioController       * fAudioController;
    IBOutlet NSTabViewItem  * fAudioTab;

    // Chapters view controller
    HBChapterTitlesController    * fChapterTitlesController;
    IBOutlet NSTabViewItem       * fChaptersTitlesTab;

    // Picture Preview
    HBPreviewController          * fPreviewController;

    // Source box
    IBOutlet NSProgressIndicator * fScanIndicator;
    IBOutlet NSBox               * fScanHorizontalLine;

    IBOutlet NSTextField         * fSrcDVD2Field;
    IBOutlet NSPopUpButton       * fSrcTitlePopUp;

    // User Preset
    HBPresetsManager             * presetManager;
    HBPresetsViewController      * fPresetsView;
}

@property (nonatomic, strong) IBOutlet NSLayoutConstraint *bottomConstrain;

@property (nonatomic, strong) HBPresetsMenuBuilder *presetsMenuBuilder;
@property (nonatomic, strong) IBOutlet NSPopUpButton *presetsPopup;
@property (nonatomic, strong) NSPopover *presetsPopover;

@property (nonatomic, weak) IBOutlet HBToolbarBadgedItem *showQueueToolbarItem;

@property (nonatomic, strong) HBSummaryViewController *summaryController;
@property (nonatomic, strong) IBOutlet NSTabViewItem *summaryTab;

@property (nonatomic, weak) IBOutlet NSView *openTitleView;
@property (nonatomic, readwrite) BOOL scanSpecificTitle;
@property (nonatomic, readwrite) NSInteger scanSpecificTitleIdx;

@property (nonatomic, readwrite, strong) HBTitleSelectionController *titlesSelectionController;

/// The current job.
@property (nonatomic, nullable) HBJob *job;
@property (nonatomic, nullable) HBAutoNamer *autoNamer;

/// The selected preset.
@property (nonatomic, nullable, strong) HBPreset *selectedPreset;

/// The current modified preset.
@property (nonatomic, strong) HBPreset *currentPreset;

/// The current destination.
@property (nonatomic, strong) NSURL *destinationURL;

/// The HBCore used for scanning.
@property (nonatomic, strong) HBCore *core;

/// The app delegate.
@property (nonatomic, strong) HBAppDelegate *delegate;

/// The queue.
@property (nonatomic, weak) HBQueue *queue;
@property (nonatomic) id observerToken;

/// Queue progress info
@property (nonatomic) IBOutlet NSTextField *statusField;
@property (nonatomic) IBOutlet NSTextField *progressField;
@property (nonatomic, copy) NSString *progress;

@property (nonatomic, readwrite) NSColor *labelColor;

/// Whether the window is visible or occluded,
/// useful to avoid updating the UI needlessly
@property (nonatomic) BOOL visible;

// Alerts
@property (nonatomic) BOOL suppressCopyProtectionWarning;

@property (nonatomic) IBOutlet NSToolbarItem *openSourceToolbarItem;
@property (nonatomic) IBOutlet NSToolbarItem *ripToolbarItem;
@property (nonatomic) IBOutlet NSToolbarItem *pauseToolbarItem;
@property (nonatomic) IBOutlet NSToolbarItem *presetsItem;

@end

@interface HBController (TouchBar) <NSTouchBarProvider, NSTouchBarDelegate>
- (void)_touchBar_updateButtonsStateForScanCore:(HBState)state;
- (void)_touchBar_updateQueueButtonsState;
- (void)_touchBar_validateUserInterfaceItems;
@end

#define WINDOW_HEIGHT_OFFSET 30

@implementation HBController

- (instancetype)initWithDelegate:(HBAppDelegate *)delegate queue:(HBQueue *)queue presetsManager:(HBPresetsManager *)manager
{
    self = [super initWithWindowNibName:@"MainWindow"];
    if (self)
    {
        // Init libhb
        NSInteger loggingLevel = [NSUserDefaults.standardUserDefaults integerForKey:HBLoggingLevel];
        _core = [[HBCore alloc] initWithLogLevel:loggingLevel name:@"ScanCore"];

        // Inits the controllers
        fPreviewController = [[HBPreviewController alloc] init];
        fPreviewController.documentController = self;

        _delegate = delegate;
        _queue = queue;

        presetManager = manager;
        _selectedPreset = manager.defaultPreset;
        _currentPreset = manager.defaultPreset;

        _scanSpecificTitleIdx = 1;
        _progress = @"";

        // Check to see if the last destination has been set, use if so, if not, use Movies
#ifdef __SANDBOX_ENABLED__
        NSData *bookmark = [NSUserDefaults.standardUserDefaults objectForKey:HBLastDestinationDirectoryBookmark];
        if (bookmark)
        {
            _destinationURL = [HBUtilities URLFromBookmark:bookmark];
        }
#else
        _destinationURL = [NSUserDefaults.standardUserDefaults URLForKey:HBLastDestinationDirectoryURL];
#endif

        if (!_destinationURL || [NSFileManager.defaultManager fileExistsAtPath:_destinationURL.path isDirectory:nil] == NO)
        {
            _destinationURL = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSMoviesDirectory, NSUserDomainMask, YES) firstObject]
                                             isDirectory:YES];
        }

#ifdef __SANDBOX_ENABLED__
        [_destinationURL startAccessingSecurityScopedResource];
#endif
    }

    return self;
}

- (void)windowDidLoad
{
    if (@available (macOS 10.12, *))
    {
        self.window.tabbingMode = NSWindowTabbingModeDisallowed;
    }

#if defined(__MAC_11_0)
    if (@available (macOS 11, *))
    {
        self.window.toolbarStyle = NSWindowToolbarStyleExpanded;
    }
#endif

    [self enableUI:NO];

    // Bottom
    self.statusField.stringValue = @"";
    self.progressField.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    [self updateProgress];

    // Register HBController's Window as a receiver for files/folders drag & drop operations
    [self.window registerForDraggedTypes:@[(NSString *)kUTTypeFileURL]];
    [fMainTabView registerForDraggedTypes:@[(NSString *)kUTTypeFileURL]];

    fPresetsView = [[HBPresetsViewController alloc] initWithPresetManager:presetManager];
    fPresetsView.delegate = self;

    // Set up the presets popover
    self.presetsPopover = [[NSPopover alloc] init];

    self.presetsPopover.contentViewController = fPresetsView;
    self.presetsPopover.contentSize = NSMakeSize(300, 580);
    self.presetsPopover.animates = YES;

    // AppKit will close the popover when the user interacts with a user interface element outside the popover.
    // note that interacting with menus or panels that become key only when needed will not cause a transient popover to close.
    self.presetsPopover.behavior = NSPopoverBehaviorSemitransient;
    self.presetsPopover.delegate = self;

    [fPresetsView view];

    // Set up the summary view
    self.summaryController = [[HBSummaryViewController alloc] init];
    self.summaryTab.view = self.summaryController.view;

    // Set up the chapters title view
    fChapterTitlesController = [[HBChapterTitlesController alloc] init];
    [fChaptersTitlesTab setView:[fChapterTitlesController view]];

    // setup the subtitles view
    fSubtitlesViewController = [[HBSubtitlesController alloc] init];
    [fSubtitlesTab setView:[fSubtitlesViewController view]];

    // setup the audio controller
    fAudioController = [[HBAudioController alloc] init];
    [fAudioTab setView:[fAudioController view]];

    // setup the video view controller
    fVideoController = [[HBVideoController alloc] init];
    [fVideoTab setView:[fVideoController view]];

    // setup the picture view controller
    fPictureViewController = [[HBPictureViewController alloc] init];
    [fPictureTab setView:[fPictureViewController view]];

    // setup the filters view controller
    fFiltersViewController = [[HBFiltersViewController alloc] init];
    [fFiltersTab setView:[fFiltersViewController view]];

    // Add the observers
    [self.core addObserver:self forKeyPath:@"state"
                   options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                   context:HBControllerScanCoreContext];

    [NSNotificationCenter.defaultCenter addObserverForName:HBQueueDidStartNotification
                                                    object:_queue queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification * _Nonnull note) {
        self.bottomConstrain.animator.constant = 0;
    }];

    [NSNotificationCenter.defaultCenter addObserverForName:HBQueueDidCompleteNotification
                                                    object:_queue queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification * _Nonnull note) {
        self.bottomConstrain.animator.constant = -WINDOW_HEIGHT_OFFSET;
        self.statusField.stringValue = @"";
        self.progress = @"";
        [self updateProgress];
    }];

    [NSNotificationCenter.defaultCenter addObserverForName:HBQueueDidStartItemNotification
                                                    object:_queue queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification * _Nonnull note) { [self setUpQueueObservers]; }];

    [NSNotificationCenter.defaultCenter addObserverForName:HBQueueDidCompleteItemNotification
                                                    object:_queue queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification * _Nonnull note) { [self setUpQueueObservers]; }];

    [NSNotificationCenter.defaultCenter addObserverForName:HBQueueDidChangeStateNotification
                                                    object:_queue queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification * _Nonnull note) {
        [self updateQueueUI];
    }];

    [self updateQueueUI];

    // Presets menu
    self.presetsMenuBuilder = [[HBPresetsMenuBuilder alloc] initWithMenu:self.presetsPopup.menu
                                                                  action:@selector(selectPresetFromMenu:)
                                                                    size:[NSFont smallSystemFontSize]
                                                          presetsManager:presetManager];
    [self.presetsMenuBuilder build];

    // Log level
    [NSUserDefaultsController.sharedUserDefaultsController addObserver:self forKeyPath:@"values.LoggingLevel"
                                                               options:0 context:HBControllerLogLevelContext];

    self.bottomConstrain.constant = -WINDOW_HEIGHT_OFFSET;

    [self.window recalculateKeyViewLoop];
}

#pragma mark - Drag & drop handling

- (nullable NSArray<NSURL *> *)fileURLsFromPasteboard:(NSPasteboard *)pasteboard
{
    NSDictionary *options = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    return [pasteboard readObjectsForClasses:@[[NSURL class]] options:options];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    NSArray<NSURL *> *fileURLs = [self fileURLsFromPasteboard:[sender draggingPasteboard]];
    [self.window.contentView setShowFocusRing:YES];
    return fileURLs.count ? NSDragOperationGeneric : NSDragOperationNone;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender
{
    return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSArray<NSURL *> *fileURLs = [self fileURLsFromPasteboard:[sender draggingPasteboard]];

    if (fileURLs.count)
    {
        [self openURL:fileURLs.firstObject];
    }

    [self.window.contentView setShowFocusRing:NO];
    return YES;
}

- (void)draggingExited:(nullable id <NSDraggingInfo>)sender
{
    [self.window.contentView setShowFocusRing:NO];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == HBControllerScanCoreContext)
    {
        HBState state = [change[NSKeyValueChangeNewKey] intValue];
        [self updateToolbarButtonsStateForScanCore:state];
        if (@available(macOS 10.12.2, *))
        {
            [self _touchBar_updateButtonsStateForScanCore:state];
            [self _touchBar_validateUserInterfaceItems];
        }
    }
    else if (context == HBControllerLogLevelContext)
    {
        self.core.logLevel = [NSUserDefaults.standardUserDefaults integerForKey:HBLoggingLevel];
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)updateQueueUI
{
    [self updateToolbarButtonsState];
    [self.window.toolbar validateVisibleItems];

    if (@available(macOS 10.12.2, *))
    {
        [self _touchBar_updateQueueButtonsState];
        [self _touchBar_validateUserInterfaceItems];
    }

    NSUInteger count = self.queue.pendingItemsCount;
    self.showQueueToolbarItem.badgeValue = count ? @(count).stringValue : @"";
}

- (void)updateToolbarButtonsStateForScanCore:(HBState)state
{
    if (state == HBStateIdle)
    {
        _openSourceToolbarItem.image = [NSImage imageNamed: @"source"];
        _openSourceToolbarItem.label = NSLocalizedString(@"Open Source",  @"Toolbar Open/Cancel Item");
        _openSourceToolbarItem.toolTip = NSLocalizedString(@"Open Source", @"Toolbar Open/Cancel Item");
    }
    else
    {
        _openSourceToolbarItem.image = [NSImage imageNamed: @"stopencode"];
        _openSourceToolbarItem.label = NSLocalizedString(@"Cancel Scan", @"Toolbar Open/Cancel Item");
        _openSourceToolbarItem.toolTip = NSLocalizedString(@"Cancel Scanning Source", @"Toolbar Open/Cancel Item");
    }
}

- (void)updateToolbarButtonsState
{
    if (self.queue.canResume)
    {
        _pauseToolbarItem.image = [NSImage imageNamed: @"encode"];
        _pauseToolbarItem.label = NSLocalizedString(@"Resume", @"Toolbar Pause Item");
        _pauseToolbarItem.toolTip = NSLocalizedString(@"Resume Encoding", @"Toolbar Pause Item");
    }
    else
    {
        _pauseToolbarItem.image = [NSImage imageNamed:@"pauseencode"];
        _pauseToolbarItem.label = NSLocalizedString(@"Pause", @"Toolbar Pause Item");
        _pauseToolbarItem.toolTip = NSLocalizedString(@"Pause Encoding", @"Toolbar Pause Item");

    }
    if (self.queue.isEncoding)
    {
        _ripToolbarItem.image = [NSImage imageNamed:@"stopencode"];
        _ripToolbarItem.label = NSLocalizedString(@"Stop", @"Toolbar Start/Stop Item");
        _ripToolbarItem.toolTip = NSLocalizedString(@"Stop Encoding", @"Toolbar Start/Stop Item");
    }
    else
    {
        _ripToolbarItem.image = [NSImage imageNamed: @"encode"];
        _ripToolbarItem.label = _queue.pendingItemsCount > 0 ? NSLocalizedString(@"Start Queue", @"Toolbar Start/Stop Item") :  NSLocalizedString(@"Start", @"Toolbar Start/Stop Item");
        _ripToolbarItem.toolTip = NSLocalizedString(@"Start Encoding", @"Toolbar Start/Stop Item");
    }
}

- (void)enableUI:(BOOL)enabled
{
    if (enabled)
    {
        self.labelColor = [NSColor controlTextColor];
    }
    else
    {
        self.labelColor = [NSColor disabledControlTextColor];
    }

    fPresetsView.enabled = enabled;
}

- (void)setNilValueForKey:(NSString *)key
{
    if ([key isEqualToString:@"scanSpecificTitleIdx"])
    {
        [self setValue:@0 forKey:key];
    }
}

#pragma mark - Queue progress

- (void)windowDidChangeOcclusionState:(NSNotification *)notification
{
    if (self.window.occlusionState & NSWindowOcclusionStateVisible)
    {
        self.visible = YES;
        [self updateProgress];
    }
    else
    {
        self.visible = NO;
    }
}

- (void)updateProgress
{
    self.progressField.stringValue = self.progress;
}

- (void)setUpQueueObservers
{
    [self removeQueueObservers];

    if (self->_queue.workingItemsCount > 1)
    {
        [self setUpForMultipleWorkers];
    }
    else if (self->_queue.workingItemsCount == 1)
    {
        [self setUpForSingleWorker];
    }
}

- (void)setUpForMultipleWorkers
{
    self.statusField.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Encoding %lu Jobs", @""), self.queue.workingItemsCount];
    self.progress = NSLocalizedString(@"Working", @"");
    [self updateProgress];
}

- (void)setUpForSingleWorker
{
    HBQueueJobItem *firstWorkingItem = nil;
    for (HBQueueJobItem *item in self.queue.items)
    {
        if (item.state == HBQueueItemStateWorking)
        {
            firstWorkingItem = item;
            break;
        }
    }

    if (firstWorkingItem)
    {
        HBQueueWorker *worker = [self.queue workerForItem:firstWorkingItem];

        if (worker)
        {
            self.observerToken = [NSNotificationCenter.defaultCenter addObserverForName:HBQueueWorkerProgressNotification
                                                                                 object:worker queue:NSOperationQueue.mainQueue
                                                                             usingBlock:^(NSNotification * _Nonnull note) {
                self.progress = note.userInfo[HBQueueWorkerProgressNotificationInfoKey];

                if (self->_visible)
                {
                    [self updateProgress];
                }
            }];
        }
    }

    self.statusField.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Encoding Job: %@", @""), firstWorkingItem.outputFileName];
}

- (void)removeQueueObservers
{
    if (self.observerToken)
    {
        [NSNotificationCenter.defaultCenter removeObserver:self.observerToken];
        self.observerToken = nil;
    }
}

#pragma mark - UI Validation

- (BOOL)validateUserIterfaceItemForAction:(SEL)action
{
    if (self.core.state == HBStateScanning)
    {
        if (action == @selector(browseSources:))
        {
            return YES;
        }
        if (action == @selector(toggleStartCancel:) || action == @selector(addToQueue:))
        {
            return NO;
        }
    }
    else if (action == @selector(browseSources:))
    {
        return YES;
    }

    if (action == @selector(toggleStartCancel:))
    {
        if (self.queue.isEncoding)
        {
            return YES;
        }
        else
        {
            return (self.job != nil || self.queue.canEncode);
        }
    }

    if (action == @selector(togglePauseResume:)) {
        return self.queue.canPause || self.queue.canResume;
    }

    if (action == @selector(addToQueue:))
    {
        return (self.job != nil);
    }

    return YES;
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
    return [self validateUserIterfaceItemForAction:anItem.action];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = menuItem.action;

    if (action == @selector(addToQueue:) || action == @selector(addAllTitlesToQueue:) ||
        action == @selector(addTitlesToQueue:) || action == @selector(showAddPresetPanel:))
    {
        return self.job && self.window.attachedSheet == nil;
    }
    if (action == @selector(selectDefaultPreset:))
    {
        return self.window.attachedSheet == nil;
    }
    if (action == @selector(togglePauseResume:))
    {
        return [self.delegate validateMenuItem:menuItem];
    }
    if (action == @selector(toggleStartCancel:))
    {
        BOOL result = [self.delegate validateMenuItem:menuItem];

        if ([menuItem.title isEqualToString:NSLocalizedString(@"Start Encoding", @"Menu Start/Stop Item")])
        {
            if (!result && self.job)
            {
                return YES;
            }
        }

        return result;
    }
    if (action == @selector(browseSources:))
    {
        if (self.core.state == HBStateScanning) {
            return NO;
        }
        else
        {
            return self.window.attachedSheet == nil;
        }
    }
    if (action == @selector(selectPresetFromMenu:))
    {
        if ([menuItem.representedObject isEqualTo:self.selectedPreset])
        {
            menuItem.state = NSControlStateValueOn;
        }
        else
        {
            menuItem.state = NSControlStateValueOff;
        }
        return (self.job != nil);
    }
    if (action == @selector(exportPreset:) ||
        action == @selector(selectDefaultPreset:))
    {
        return self.job != nil;
    }
    if (action == @selector(deletePreset:) ||
        action == @selector(setDefaultPreset:))
    {
        return self.job != nil && self.selectedPreset;
    }
    if (action == @selector(savePreset:))
    {
        return self.job != nil && self.selectedPreset && self.selectedPreset.isBuiltIn == NO;
    }
    if (action == @selector(showRenamePresetPanel:))
    {
        return self.selectedPreset && self.selectedPreset.isBuiltIn == NO;
    }

    return YES;
}

#pragma mark - Get New Source

- (void)launchAction
{
    if (self.core.state != HBStateScanning && !self.job)
    {
        if ([NSUserDefaults.standardUserDefaults boolForKey:HBShowOpenPanelAtLaunch])
        {
            [self browseSources:self];
        }
    }
}

- (NSModalResponse)runCopyProtectionAlert
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Copy-Protected sources are not supported.", @"Copy Protection Alert -> message")];
    [alert setInformativeText:NSLocalizedString(@"Please note that HandBrake does not support the removal of copy-protection from DVD Discs. You can if you wish use any other 3rd party software for this function. This warning will be shown only once each time HandBrake is run.", @"Copy Protection Alert -> informative text")];
    [alert addButtonWithTitle:NSLocalizedString(@"Attempt Scan Anyway", @"Copy Protection Alert -> first button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Copy Protection Alert -> second button")];

    [NSApp requestUserAttention:NSCriticalRequest];

    return [alert runModal];
}

/**
 * Here we actually tell hb_scan to perform the source scan, using the path to source and title number
 */
- (void)scanURL:(NSURL *)fileURL titleIndex:(NSUInteger)index completionHandler:(void(^)(NSArray<HBTitle *> *titles))completionHandler
{
    // Save the current settings
    if (self.job)
    {
        self.currentPreset = [self createPresetFromCurrentSettings];
    }

    self.job = nil;
    [fSrcTitlePopUp removeAllItems];
    self.window.representedURL = nil;
    self.window.title = NSLocalizedString(@"HandBrake", @"Main Window -> title");

    NSURL *mediaURL = [HBUtilities mediaURLFromURL:fileURL];

    NSError *outError = NULL;

    // Check if we can scan the source and if there is any warning.
    BOOL canScan = [self.core canScan:mediaURL error:&outError];

    // Notify the user that we don't support removal of copy protection.
    if (canScan && [outError code] == 101 && !self.suppressCopyProtectionWarning)
    {
        self.suppressCopyProtectionWarning = YES;
        if ([self runCopyProtectionAlert] == NSAlertFirstButtonReturn)
        {
            // User chose to override our warning and scan the physical dvd anyway, at their own peril. on an encrypted dvd this produces massive log files and fails
            [HBUtilities writeToActivityLog:"User overrode copy-protection warning - trying to open physical dvd without decryption"];
        }
        else
        {
            // User chose to cancel the scan
            [HBUtilities writeToActivityLog:"Cannot open physical dvd, scan canceled"];
            canScan = NO;
        }
    }

    if (canScan)
    {
        NSUInteger hb_num_previews = [NSUserDefaults.standardUserDefaults integerForKey:HBPreviewsNumber];
        NSUInteger min_title_duration_seconds = [NSUserDefaults.standardUserDefaults integerForKey:HBMinTitleScanSeconds];

        [self.core scanURL:mediaURL
                titleIndex:index
                  previews:hb_num_previews minDuration:min_title_duration_seconds keepPreviews:YES
           progressHandler:^(HBState state, HBProgress progress, NSString *info)
         {
             self->fSrcDVD2Field.stringValue = info;
             self->fScanIndicator.hidden = NO;
             self->fScanHorizontalLine.hidden = YES;
             self->fScanIndicator.doubleValue = progress.percent;
         }
         completionHandler:^(HBCoreResult result)
         {
             self->fScanHorizontalLine.hidden = NO;
             self->fScanIndicator.hidden = YES;
             self->fScanIndicator.indeterminate = NO;
             self->fScanIndicator.doubleValue = 0.0;

             if (result == HBCoreResultDone)
             {
                 for (HBTitle *title in self.core.titles)
                 {
                     [self->fSrcTitlePopUp addItemWithTitle:title.description];
                 }
                 self.window.representedURL = mediaURL;
                 self.window.title = mediaURL.lastPathComponent;
             }
             else
             {
                 // We display a message if a valid source was not chosen
                 self->fSrcDVD2Field.stringValue = NSLocalizedString(@"No Valid Source Found", @"Main Window -> Info text");
             }

             // Set the last searched source directory in the prefs here
             if ([NSWorkspace.sharedWorkspace isFilePackageAtPath:mediaURL.URLByDeletingLastPathComponent.path])
             {
                 [NSUserDefaults.standardUserDefaults setURL:mediaURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent forKey:HBLastSourceDirectoryURL];
             }
             else
             {
                 [NSUserDefaults.standardUserDefaults setURL:mediaURL.URLByDeletingLastPathComponent forKey:HBLastSourceDirectoryURL];
             }

             completionHandler(self.core.titles);
             [self.window.toolbar validateVisibleItems];
             if (@available(macOS 10.12.2, *))
             {
                 [self _touchBar_validateUserInterfaceItems];
             }
         }];
    }
    else
    {
        completionHandler(@[]);
    }
}

- (void)openURL:(NSURL *)fileURL titleIndex:(NSUInteger)index
{
    [self showWindow:self];

    [self scanURL:fileURL titleIndex:index completionHandler:^(NSArray<HBTitle *> *titles)
    {
        if (titles.count)
        {
            [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:fileURL];

            HBTitle *featuredTitle = titles.firstObject;
            for (HBTitle *title in titles)
            {
                if (title.isFeatured)
                {
                    featuredTitle = title;
                }
            }

            HBJob *job = [self jobFromTitle:featuredTitle];
            self.job = job;
        }
    }];
}

- (void)openURL:(NSURL *)fileURL
{
    if (self.core.state != HBStateScanning)
    {
        [self openURL:fileURL titleIndex:0];
    }
}

/**
 * Rescans the a job back into the main window
 */
- (void)openJob:(HBJob *)job completionHandler:(void (^)(BOOL result))handler
{
    if (self.core.state != HBStateScanning)
    {
        [job refreshSecurityScopedResources];
        [self scanURL:job.fileURL titleIndex:job.titleIdx completionHandler:^(NSArray<HBTitle *> *titles)
        {
            if (titles.count)
            {
                // If the scan was cached, reselect
                // the original title
                for (HBTitle *title in titles)
                {
                    if (title.index == job.titleIdx)
                    {
                        job.title = title;
                        break;
                    }
                }

                // Else just one title or a title specific rescan
                // select the first title
                if (!job.title)
                {
                    job.title = titles.firstObject;
                }

                self.selectedPreset = nil;
                self.job = job;

                handler(YES);
            }
            else
            {
                handler(NO);
            }
        }];
    }
    else
    {
        handler(NO);
    }
}

- (HBJob *)jobFromTitle:(HBTitle *)title
{
    // If there is already a title load, save the current settings to a preset
    if (self.job)
    {
        self.currentPreset = [self createPresetFromCurrentSettings];
    }

    HBJob *job = [[HBJob alloc] initWithTitle:title andPreset:self.currentPreset];
    job.outputURL = self.destinationURL;

    // If the source is not a stream, and autonaming is disabled,
    // keep the existing file name.
    if (self.job.outputFileName.length == 0 || title.isStream || [NSUserDefaults.standardUserDefaults boolForKey:HBDefaultAutoNaming])
    {
        job.outputFileName = job.defaultName;
    }
    else
    {
        job.outputFileName = self.job.outputFileName;
    }

    return job;
}

- (void)removeJobObservers
{
    if (self.job)
    {
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center removeObserver:self name:HBContainerChangedNotification object:_job];
        [center removeObserver:self name:HBPictureChangedNotification object:_job.picture];
        [center removeObserver:self name:HBFiltersChangedNotification object:_job.filters];
        [center removeObserver:self name:HBVideoChangedNotification object:_job.video];
        self.autoNamer = nil;
    }
}

/**
 *  Observe the job settings changes.
 *  This is used to update the file name and extension
 *  and the custom preset string.
 */
- (void)addJobObservers
{
    if (self.job)
    {
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(formatChanged:) name:HBContainerChangedNotification object:_job];
        [center addObserver:self selector:@selector(customSettingUsed) name:HBPictureChangedNotification object:_job.picture];
        [center addObserver:self selector:@selector(customSettingUsed) name:HBFiltersChangedNotification object:_job.filters];
        [center addObserver:self selector:@selector(customSettingUsed) name:HBVideoChangedNotification object:_job.video];
        self.autoNamer = [[HBAutoNamer alloc] initWithJob:self.job];
    }
}

- (void)setJob:(HBJob *)job
{
    [self removeJobObservers];

    // Clear the undo manager
    [_job.undo removeAllActions];
    _job.undo = nil;

    // Retain the new job
    _job = job;

    job.undo = self.window.undoManager;

    // Set the jobs info to the view controllers
    self.summaryController.job = job;
    fPictureViewController.picture = job.picture;
    fFiltersViewController.filters = job.filters;
    fVideoController.video = job.video;
    fAudioController.audio = job.audio;
    fSubtitlesViewController.subtitles = job.subtitles;
    fChapterTitlesController.job = job;

    if (job)
    {
        HBPreviewGenerator *generator = [[HBPreviewGenerator alloc] initWithCore:self.core job:job];
        fPreviewController.generator = generator;
        self.summaryController.generator = generator;

        HBTitle *title = job.title;

        // Update the title selection popup.
        [fSrcTitlePopUp selectItemWithTitle:title.description];

        // Grok the output file name from title.name upon title change
        if (title.isStream && self.core.titles.count > 1)
        {
            // Change the source to read out the parent folder also
            fSrcDVD2Field.stringValue = [NSString stringWithFormat:@"%@/%@, %@", title.url.URLByDeletingLastPathComponent.lastPathComponent, title.name, title.shortFormatDescription];
        }
        else
        {
            fSrcDVD2Field.stringValue = [NSString stringWithFormat:@"%@, %@", title.name, title.shortFormatDescription];
        }
    }
    else
    {
        [fPreviewController.generator invalidate];
        fPreviewController.generator = nil;
        self.summaryController.generator = nil;
    }
    fPreviewController.picture = job.picture;

    [self enableUI:(job != nil)];

    [self addJobObservers];
}

/**
 * Opens the source browse window, called from Open Source widgets
 */
- (IBAction)browseSources:(id)sender
{
    if (self.core.state == HBStateScanning)
    {
        [self.core cancelScan];
        return;
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:YES];

    NSURL *sourceDirectory;
	if ([NSUserDefaults.standardUserDefaults URLForKey:HBLastSourceDirectoryURL])
	{
		sourceDirectory = [NSUserDefaults.standardUserDefaults URLForKey:HBLastSourceDirectoryURL];
	}
	else
	{
        sourceDirectory = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) firstObject]
                                                       isDirectory:YES];
	}

    panel.directoryURL = sourceDirectory;
    panel.accessoryView = self.openTitleView;
    panel.accessoryViewDisclosed = YES;

    [panel beginSheetModalForWindow:self.window completionHandler: ^(NSInteger result)
    {
        if (result == NSModalResponseOK)
         {
             NSInteger titleIdx = self.scanSpecificTitle ? self.scanSpecificTitleIdx : 0;
             [self openURL:panel.URL titleIndex:titleIdx];
         }
     }];
}

#pragma mark - GUI Controls Changed Methods

- (IBAction)browseDestination:(id)sender
{
    // Open a panel to let the user choose and update the text field
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    panel.prompt = NSLocalizedString(@"Choose", @"Main Window -> Destination open panel");

    if (self.job.outputURL)
    {
        panel.directoryURL = self.job.outputURL;
    }

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result)
     {
         if (result == NSModalResponseOK)
         {
             self.job.outputURL = panel.URL;
             self.destinationURL = panel.URL;

             // Save this path to the prefs so that on next browse destination window it opens there
             [NSUserDefaults.standardUserDefaults setObject:[HBUtilities bookmarkFromURL:panel.URL]
                                                       forKey:HBLastDestinationDirectoryBookmark];
             [NSUserDefaults.standardUserDefaults setURL:panel.URL
                                                  forKey:HBLastDestinationDirectoryURL];

         }
     }];
}

- (IBAction)titlePopUpChanged:(NSPopUpButton *)sender
{
    HBTitle *title = self.core.titles[sender.indexOfSelectedItem];
    HBJob *job = [self jobFromTitle:title];
    self.job = job;
}

- (void)formatChanged:(NSNotification *)notification
{
    [self customSettingUsed];
}

/**
 * Method to determine if we should change the UI
 * To reflect whether or not a Preset is being used or if
 * the user is using "Custom" settings by determining the sender
 */
- (void)customSettingUsed
{
    // Update the preset and file name only if we are not
    // undoing or redoing, because if so it's already stored
    // in the undo manager.
    NSUndoManager *undo = self.window.undoManager;
    if (!(undo.isUndoing || undo.isRedoing))
    {
        // Change UI to show "Custom" settings are being used
        if (![self.job.presetName hasSuffix:NSLocalizedString(@"(Modified)", @"Main Window -> preset modified")])
        {
            self.job.presetName = [NSString stringWithFormat:@"%@ %@", self.job.presetName, NSLocalizedString(@"(Modified)", @"Main Window -> preset modified")];
        }
    }
}

#pragma mark - Job Handling

/**
 Check if the job destination if a valid one,
 if so, call the handler
 @param job the job
 @param completionHandler the block to call if the check is successful
 */
- (void)runDestinationAlerts:(HBJob *)job completionHandler:(void (^ __nullable)(NSModalResponse returnCode))handler
{
    if ([NSFileManager.defaultManager fileExistsAtPath:job.outputURL.path] == NO)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"Warning!", @"Invalid destination alert -> message")];
        [alert setInformativeText:NSLocalizedString(@"This is not a valid destination directory!", @"Invalid destination alert -> informative text")];
        [alert setAlertStyle:NSAlertStyleCritical];
        [alert beginSheetModalForWindow:self.window completionHandler:handler];
    }
    else if ([job.fileURL isEqual:job.completeOutputURL]||
             [job.fileURL.absoluteString.lowercaseString isEqualToString:job.completeOutputURL.absoluteString.lowercaseString])
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"A file already exists at the selected destination.", @"Destination same as source alert -> message")];
        [alert setInformativeText:NSLocalizedString(@"The destination is the same as the source, you can not overwrite your source file!", @"Destination same as source alert -> informative text")];
        [alert setAlertStyle:NSAlertStyleCritical];
        [alert beginSheetModalForWindow:self.window completionHandler:handler];
    }
    else if ([NSFileManager.defaultManager fileExistsAtPath:job.completeOutputURL.path])
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"A file already exists at the selected destination.", @"File already exists alert -> message")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Do you want to overwrite %@?", @"File already exists alert -> informative text"), job.completeOutputURL.path]];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"File already exists alert -> first button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Overwrite", @"File already exists alert -> second button")];
#if defined(__MAC_11_0)
    if (@available(macOS 11, *))
    {
        alert.buttons.lastObject.hasDestructiveAction = true;
    }
#endif
        [alert setAlertStyle:NSAlertStyleCritical];

        [alert beginSheetModalForWindow:self.window completionHandler:handler];
    }
    else if ([_queue itemExistAtURL:job.completeOutputURL])
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"There is already a queue item for this destination.", @"File already exists in queue alert -> message")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Do you want to overwrite %@?", @"File already exists in queue alert -> informative text"), job.completeOutputURL.path]];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"File already exists in queue alert -> first button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Overwrite", @"File already exists in queue alert -> second button")];
#if defined(__MAC_11_0)
    if (@available(macOS 11, *))
    {
        alert.buttons.lastObject.hasDestructiveAction = true;
    }
#endif
        [alert setAlertStyle:NSAlertStyleCritical];

        [alert beginSheetModalForWindow:self.window completionHandler:handler];
    }
    else
    {
        handler(NSAlertSecondButtonReturn);
    }
}

/**
 *  Actually adds a job to the queue
 */
- (void)doAddToQueue
{
    [_queue addJob:[self.job copy]];
}

/**
 * Puts up an alert before ultimately calling doAddToQueue
 */
- (IBAction)addToQueue:(id)sender
{
    if ([self.window HB_endEditing])
    {
        [self runDestinationAlerts:self.job completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertSecondButtonReturn)
            {
                [self doAddToQueue];
            }
        }];
    }
}

- (void)doRip
{
    // if there are no jobs in the queue, then add this one to the queue and rip
    // otherwise, just rip the queue
    if (_queue.pendingItemsCount == 0)
    {
        [self doAddToQueue];
    }

    [_delegate toggleStartCancel:self];
}

/**
 * Puts up an alert before ultimately calling doRip
 */
- (IBAction)toggleStartCancel:(id)sender
{
    // Rip or Cancel ?
    if (_queue.isEncoding || _queue.canEncode)
	{
        // Displays an alert asking user if the want to cancel encoding of current job.
        [_delegate toggleStartCancel:self];
    }
    else
    {
        if ([self.window HB_endEditing])
        {
            [self runDestinationAlerts:self.job completionHandler:^(NSModalResponse returnCode) {
                if (returnCode == NSAlertSecondButtonReturn)
                {
                    [self doRip];
                }
            }];
        }
    }
}

- (IBAction)togglePauseResume:(id)sender
{
    [_delegate togglePauseResume:sender];
}

#pragma mark -
#pragma mark Batch Queue Titles Methods

- (IBAction)addTitlesToQueue:(id)sender
{
    [self.window HB_endEditing];

    self.titlesSelectionController = [[HBTitleSelectionController alloc] initWithTitles:self.core.titles
                                                                             presetName:self.job.presetName
                                                                               delegate:self];

    [self.window beginSheet:self.titlesSelectionController.window completionHandler:nil];
}

- (void)didSelectTitles:(NSArray<HBTitle *> *)titles
{
    [self.window endSheet:self.titlesSelectionController.window];

    [self doAddTitlesToQueue:titles];
}

- (void)doAddTitlesToQueue:(NSArray<HBTitle *> *)titles
{
    NSMutableArray<HBJob *> *jobs = [[NSMutableArray alloc] init];
    BOOL fileExists = NO;
    BOOL fileOverwritesSource = NO;

    // Get the preset from the loaded job.
    HBPreset *preset = [self createPresetFromCurrentSettings];

    for (HBTitle *title in titles)
    {
        HBJob *job = [[HBJob alloc] initWithTitle:title andPreset:preset];
        job.outputURL = self.destinationURL;
        job.outputFileName = job.defaultName;
        job.title = nil;
        [jobs addObject:job];
    }

    NSMutableSet<NSURL *> *destinations = [[NSMutableSet alloc] init];
    for (HBJob *job in jobs)
    {
        if ([destinations containsObject:job.completeOutputURL])
        {
            fileExists = YES;
            break;
        }
        else
        {
            [destinations addObject:job.completeOutputURL];
        }

        if ([[NSFileManager defaultManager] fileExistsAtPath:job.completeOutputURL.path] || [_queue itemExistAtURL:job.completeOutputURL])
        {
            fileExists = YES;
            break;
        }
    }

    for (HBJob *job in jobs)
    {
        if ([job.fileURL isEqual:job.completeOutputURL]) {
            fileOverwritesSource = YES;
            break;
        }
    }

    if (fileOverwritesSource)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"A file already exists at the selected destination.", @"Destination same as source alert -> message")];
        [alert setInformativeText:NSLocalizedString(@"The destination is the same as the source, you can not overwrite your source file!", @"Destination same as source alert -> informative text")];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
    else if (fileExists)
    {
        // File exist, warn user
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"File already exists.", @"File already exists alert -> message")];
        [alert setInformativeText:NSLocalizedString(@"One or more file already exists. Do you want to overwrite?", @"File already exists alert -> informative text")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"File already exists alert -> first button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Overwrite", @"File already exists alert -> second button")];
#if defined(__MAC_11_0)
    if (@available(macOS 11, *))
    {
        alert.buttons.lastObject.hasDestructiveAction = true;
    }
#endif
        [alert setAlertStyle:NSAlertStyleCritical];

        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertSecondButtonReturn)
            {
                [self->_queue addJobs:jobs];
            }
        }];
    }
    else
    {
        [_queue addJobs:jobs];
    }
}

- (IBAction)addAllTitlesToQueue:(id)sender
{
    [self doAddTitlesToQueue:self.core.titles];
}

#pragma mark - Picture

- (IBAction)showPreviewWindow:(id)sender
{
	[fPreviewController showWindow:sender];
}

- (IBAction)showTabView:(id)sender
{
    NSInteger tag = [sender tag];
    [fMainTabView selectTabViewItemAtIndex:tag];
}

#pragma mark - Presets View Controller Delegate

- (void)selectionDidChange
{
    self.selectedPreset = fPresetsView.selectedPreset;
    [self applyPreset:fPresetsView.selectedPreset];
}

#pragma mark -  Presets

- (BOOL)popoverShouldDetach:(NSPopover *)popover
{
    if (popover == self.presetsPopover) {
        return YES;
    }

    return NO;
}

- (IBAction)togglePresets:(id)sender
{
    if (self.presetsPopover)
    {
        if (!self.presetsPopover.isShown)
        {
            NSView *target = [sender isKindOfClass:[NSView class]] ? (NSView *)sender : self.presetsItem.view.window ? self.presetsItem.view : self.window.contentView;
            [self.presetsPopover showRelativeToRect:target.bounds ofView:target preferredEdge:NSMaxYEdge];
        }
        else
        {
            [self.presetsPopover close];
        }
    }
}

- (void)setSelectedPreset:(HBPreset *)selectedPreset
{
    if (selectedPreset != _selectedPreset)
    {
        NSUndoManager *undo = self.window.undoManager;
        [[undo prepareWithInvocationTarget:self] setSelectedPreset:_selectedPreset];

        _selectedPreset = selectedPreset;
    }
}

- (void)setCurrentPreset:(HBPreset *)currentPreset
{
    NSParameterAssert(currentPreset);

    if (currentPreset != _currentPreset)
    {
        NSUndoManager *undo = self.window.undoManager;
        [[undo prepareWithInvocationTarget:self] setCurrentPreset:_currentPreset];

        _currentPreset = currentPreset;
    }
}

- (IBAction)reloadPreset:(id)sender
{
    HBPreset *preset = self.selectedPreset ? self.selectedPreset : self.currentPreset;
    if (preset)
    {
        [self applyPreset:preset];
    }
}

- (void)applyPreset:(HBPreset *)preset
{
    NSParameterAssert(preset);

    if (self.job)
    {
        self.currentPreset = preset;

        // Remove the job observer so we don't update the file name
        // too many times while the preset is being applied
        [self removeJobObservers];

        // Apply the preset to the current job
        [self.job applyPreset:self.currentPreset];

        [self addJobObservers];

        [self.autoNamer updateFileExtension];

        // If Auto Naming is on, update the destination
        [self.autoNamer updateFileName];
    }
}

- (IBAction)showAddPresetPanel:(id)sender
{
    [self.window HB_endEditing];

    // Show the add panel
    HBAddPresetController *addPresetController = [[HBAddPresetController alloc] initWithPreset:[self createPresetFromCurrentSettings]
                                                                                 presetManager:presetManager
                                                                                   customWidth:self.job.picture.maxWidth
                                                                                  customHeight:self.job.picture.maxHeight
                                                                           resolutionLimitMode:self.job.picture.resolutionLimitMode];

    [self.window beginSheet:addPresetController.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK)
        {
            self.selectedPreset = addPresetController.preset;
            [self applyPreset:addPresetController.preset];
            self->fPresetsView.selectedPreset = addPresetController.preset;
        }
    }];
}

- (HBMutablePreset *)createPresetFromCurrentSettings
{
    HBMutablePreset *preset = [self.currentPreset mutableCopy];
    [self.job writeToPreset:preset];
    return preset;
}

- (IBAction)showRenamePresetPanel:(id)sender
{
    [self.window HB_endEditing];

    __block HBRenamePresetController *renamePresetController = [[HBRenamePresetController alloc] initWithPreset:self.selectedPreset
                                                                                          presetManager:presetManager];
    [self.window beginSheet:renamePresetController.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK)
        {
            self.job.presetName = renamePresetController.preset.name;
        }
        renamePresetController = nil;
    }];
}

#pragma mark - Import Export Preset(s)

- (IBAction)exportPreset:(id)sender
{
    fPresetsView.selectedPreset = self.selectedPreset;
    [fPresetsView exportPreset:sender];
}

- (IBAction)importPreset:(id)sender
{
    [fPresetsView importPreset:sender];
}

#pragma mark - Preset Menu

- (IBAction)selectDefaultPreset:(id)sender
{
    self.selectedPreset = presetManager.defaultPreset;
    [self applyPreset:presetManager.defaultPreset];
    fPresetsView.selectedPreset = presetManager.defaultPreset;
}

- (IBAction)setDefaultPreset:(id)sender
{
    [presetManager setDefaultPreset:self.selectedPreset];
}

- (IBAction)savePreset:(id)sender
{
    [self.window HB_endEditing];

    NSIndexPath *indexPath = [presetManager indexPathOfPreset:self.selectedPreset];
    if (indexPath)
    {
        HBMutablePreset *preset = [self createPresetFromCurrentSettings];
        preset.name = self.selectedPreset.name;
        preset.isDefault = self.selectedPreset.isDefault;

        [presetManager replacePresetAtIndexPath:indexPath withPreset:preset];

        self.job.presetName = preset.name;
        self.selectedPreset = preset;
        fPresetsView.selectedPreset = preset;

        [self.window.undoManager removeAllActions];
    }
}

- (IBAction)deletePreset:(id)sender
{
    fPresetsView.selectedPreset = self.selectedPreset;
    [fPresetsView deletePreset:self];
}

- (IBAction)insertCategory:(id)sender
{
    [fPresetsView insertCategory:sender];
}

- (IBAction)selectPresetFromMenu:(id)sender
{
    // Retrieve the preset stored in the NSMenuItem
    HBPreset *preset = [sender representedObject];

    self.selectedPreset = preset;
    [self applyPreset:preset];
    fPresetsView.selectedPreset = preset;
}

@end

@implementation HBController (TouchBar)

@dynamic touchBar;

static NSTouchBarItemIdentifier HBTouchBarMain = @"fr.handbrake.mainWindowTouchBar";

static NSTouchBarItemIdentifier HBTouchBarOpen = @"fr.handbrake.openSource";
static NSTouchBarItemIdentifier HBTouchBarAddToQueue = @"fr.handbrake.addToQueue";
static NSTouchBarItemIdentifier HBTouchBarAddTitlesToQueue = @"fr.handbrake.addTitlesToQueue";
static NSTouchBarItemIdentifier HBTouchBarRip = @"fr.handbrake.rip";
static NSTouchBarItemIdentifier HBTouchBarPause = @"fr.handbrake.pause";
static NSTouchBarItemIdentifier HBTouchBarPreview = @"fr.handbrake.preview";
static NSTouchBarItemIdentifier HBTouchBarActivity = @"fr.handbrake.activity";

- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *bar = [[NSTouchBar alloc] init];
    bar.delegate = self;

    bar.defaultItemIdentifiers = @[HBTouchBarOpen, NSTouchBarItemIdentifierFixedSpaceSmall, HBTouchBarAddToQueue, NSTouchBarItemIdentifierFixedSpaceLarge, HBTouchBarRip, HBTouchBarPause, NSTouchBarItemIdentifierFixedSpaceLarge, HBTouchBarPreview, HBTouchBarActivity, NSTouchBarItemIdentifierOtherItemsProxy];

    bar.customizationIdentifier = HBTouchBarMain;
    bar.customizationAllowedItemIdentifiers = @[HBTouchBarOpen, HBTouchBarAddToQueue, HBTouchBarAddTitlesToQueue, HBTouchBarRip, HBTouchBarPause, HBTouchBarPreview, HBTouchBarActivity, NSTouchBarItemIdentifierFlexibleSpace];

    return bar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualTo:HBTouchBarOpen])
    {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.customizationLabel = NSLocalizedString(@"Open Source", @"Touch bar");

        NSButton *button = [NSButton buttonWithTitle:NSLocalizedString(@"Open Source", @"Touch bar") target:self action:@selector(browseSources:)];

        item.view = button;
        return item;
    }
    else if ([identifier isEqualTo:HBTouchBarAddToQueue])
    {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.customizationLabel = NSLocalizedString(@"Add To Queue", @"Touch bar");

        NSButton *button = [NSButton buttonWithTitle:NSLocalizedString(@"Add To Queue", @"Touch bar") target:self action:@selector(addToQueue:)];

        item.view = button;
        return item;
    }
    else if ([identifier isEqualTo:HBTouchBarAddTitlesToQueue])
    {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.customizationLabel = NSLocalizedString(@"Add Titles To Queue", @"Touch bar");

        NSButton *button = [NSButton buttonWithTitle:NSLocalizedString(@"Add Titles To Queue", @"Touch bar") target:self action:@selector(addTitlesToQueue:)];

        item.view = button;
        return item;
    }
    else if ([identifier isEqualTo:HBTouchBarRip])
    {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.customizationLabel = NSLocalizedString(@"Start/Stop Encoding", @"Touch bar");

        NSButton *button = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameTouchBarPlayTemplate] target:self action:@selector(toggleStartCancel:)];

        item.view = button;
        return item;
    }
    else if ([identifier isEqualTo:HBTouchBarPause])
    {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.customizationLabel = NSLocalizedString(@"Pause Encoding", @"Touch bar");

        NSButton *button = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameTouchBarPauseTemplate] target:self action:@selector(togglePauseResume:)];

        item.view = button;
        return item;
    }
    else if ([identifier isEqualTo:HBTouchBarPreview])
    {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.customizationLabel = NSLocalizedString(@"Show Preview Window", @"Touch bar");

        NSButton *button = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameTouchBarQuickLookTemplate] target:self action:@selector(showPreviewWindow:)];

        item.view = button;
        return item;
    }
    else if ([identifier isEqualTo:HBTouchBarActivity])
    {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.customizationLabel = NSLocalizedString(@"Show Activity Window", @"Touch bar");

        NSButton *button = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameTouchBarGetInfoTemplate] target:nil action:@selector(showOutputPanel:)];

        item.view = button;
        return item;
    }

    return nil;
}

- (void)_touchBar_updateButtonsStateForScanCore:(HBState)state
{
    NSButton *openButton = (NSButton *)[[self.touchBar itemForIdentifier:HBTouchBarOpen] view];

    if (state == HBStateIdle)
    {
        openButton.title = NSLocalizedString(@"Open Source", @"Touch bar");
        openButton.bezelColor = nil;
    }
    else
    {
        openButton.title = NSLocalizedString(@"Cancel Scan", @"Touch bar");
        openButton.bezelColor = [NSColor systemRedColor];
    }
}

- (void)_touchBar_updateQueueButtonsState
{
    NSButton *ripButton = (NSButton *)[[self.touchBar itemForIdentifier:HBTouchBarRip] view];
    NSButton *pauseButton = (NSButton *)[[self.touchBar itemForIdentifier:HBTouchBarPause] view];

    if (self.queue.isEncoding)
    {
        ripButton.image = [NSImage imageNamed:NSImageNameTouchBarRecordStopTemplate];
    }
    else
    {
        ripButton.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
    }

    if (self.queue.canResume)
    {
        pauseButton.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
    }
    else
    {
        pauseButton.image = [NSImage imageNamed:NSImageNameTouchBarPauseTemplate];
    }
}

- (void)_touchBar_validateUserInterfaceItems
{
    for (NSTouchBarItemIdentifier identifier in self.touchBar.itemIdentifiers) {
        NSTouchBarItem *item = [self.touchBar itemForIdentifier:identifier];
        NSView *view = item.view;
        if ([view isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)view;
            BOOL enabled = [self validateUserIterfaceItemForAction:button.action];
            button.enabled = enabled;
        }
    }
}

@end
