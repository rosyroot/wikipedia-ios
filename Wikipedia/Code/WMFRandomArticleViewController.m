#import "WMFRandomArticleViewController.h"
#import "WMFRandomArticleFetcher.h"
#import "MWKSite.h"
#import "MWKSearchResult.h"
#import "Wikipedia-Swift.h"

static const CGFloat WMFRandomAnimationDurationFade = 0.5;


static const CGFloat WMFRandomAnimationDurationShowDice  = 0.4;
static const CGFloat WMFRandomAnimationDurationHideDice  = 0.5;
static const CGFloat WMFRandomAnimationSpringDampingDice = 0.5;

@interface WMFRandomArticleViewController ()

@property (nonatomic, strong) WMFRandomArticleFetcher* randomArticleFetcher;
@property (nonatomic, strong) MWKSite* site;

@property (nonatomic, strong) UIButton* randomButton;
@property (nonatomic, strong) UIView* emptyFadeView;

@property (nonatomic, getter = isRandomButtonHidden) BOOL randomButtonHidden;
@property (nonatomic, getter = viewHasAppeared) BOOL viewAppeared;

@property (nonatomic) CGFloat previousContentOffsetY;

@end

@implementation WMFRandomArticleViewController

- (instancetype)initWithRandomArticleFetcher:(WMFRandomArticleFetcher*)randomArticleFetcher site:(MWKSite*)site dataStore:(MWKDataStore*)dataStore {
    NSParameterAssert(dataStore);
    self = [super initWithDataStore:dataStore];
    if (self) {
        self.site                 = site;
        self.randomArticleFetcher = randomArticleFetcher;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupEmptyFadeView];
    [self setupRandomButton];

    [self loadRandomArticle:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.viewAppeared = YES;
}

- (void)setupRandomButton {
    self.randomButton = [UIButton buttonWithType:UIButtonTypeCustom];

    self.randomButton.backgroundColor = [UIColor wmf_blueTintColor];
    [self.randomButton setTitle:@"!" forState:UIControlStateNormal];
    [self.randomButton addTarget:self action:@selector(loadRandomArticle:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.randomButton];
    [self setRandomButtonHidden:YES animated:NO];
}

- (void)setupEmptyFadeView {
    self.emptyFadeView                  = [[UIView alloc] initWithFrame:self.view.bounds];
    self.emptyFadeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.emptyFadeView.backgroundColor  = [UIColor whiteColor];
    self.emptyFadeView.alpha            = 0;
    [self.view addSubview:self.emptyFadeView];
}

#pragma mark - Loading

- (void)loadRandomArticle:(id)sender {
    [self configureViewsForRandomArticleLoading:true];
    [self.randomArticleFetcher fetchRandomArticleWithSite:self.site failure:^(NSError* error) {
        [[WMFAlertManager sharedInstance] showErrorAlert:error
                                                  sticky:NO
                                   dismissPreviousAlerts:NO
                                             tapCallBack:NULL];
        [self configureViewsForRandomArticleLoading:false];
    } success:^(MWKSearchResult* searchResult) {
        self.articleTitle = [self.site titleWithString:searchResult.displayTitle];
        [self fetchArticleForce:YES completion:^{
            [self configureViewsForRandomArticleLoading:false];
            [self setRandomButtonHidden:NO animated:YES];
        }];
    }];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutRandomButtonForViewBounds:self.view.bounds hidden:self.isRandomButtonHidden];
}

- (void)layoutRandomButtonForViewBounds:(CGRect)bounds hidden:(BOOL)hidden {
    CGSize randomButtonSize     = CGSizeMake(44, 44);
    CGFloat randomButtonOriginX = (0.5 * bounds.size.width - 0.5 * randomButtonSize.width);
    CGFloat randomButtonOriginY = hidden ? bounds.size.height : bounds.size.height - 100;
    CGPoint randomButtonOrigin  = CGPointMake(randomButtonOriginX, randomButtonOriginY);
    self.randomButton.frame = (CGRect){randomButtonOrigin, randomButtonSize};
}

- (void)configureViewsForRandomArticleLoading:(BOOL)isRandomArticleLoading {
    self.randomButton.enabled = !isRandomArticleLoading;
    [UIView animateWithDuration:WMFRandomAnimationDurationFade animations:^{
        self.emptyFadeView.alpha = isRandomArticleLoading ? 1 : 0;
    } completion:^(BOOL finished) {
        if (finished && isRandomArticleLoading) {
            [self showEmptyArticle];
        }
    }];
}

- (void)setRandomButtonHidden:(BOOL)randomButtonHidden animated:(BOOL)animated {
    if (self.randomButtonHidden == randomButtonHidden) {
        return;
    }
    self.randomButtonHidden = randomButtonHidden;
    CGFloat duration            = randomButtonHidden ? WMFRandomAnimationDurationHideDice : WMFRandomAnimationDurationShowDice;
    dispatch_block_t hideOrShow = ^{
        [self layoutRandomButtonForViewBounds:self.view.bounds hidden:randomButtonHidden];
    };
    [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:WMFRandomAnimationSpringDampingDice initialSpringVelocity:0 options:0 animations:hideOrShow completion:NULL];
}

#pragma mark - WebViewControllerDelegate

- (void)webViewController:(WebViewController*)controller scrollViewDidScroll:(UIScrollView*)scrollView {
    if ([WMFArticleViewController instancesRespondToSelector:@selector(webViewController:scrollViewDidScroll:)]) {
        [super webViewController:controller scrollViewDidScroll:scrollView];
    }

    if (!self.viewHasAppeared) {
        return;
    }

    CGFloat newContentOffsetY = scrollView.contentOffset.y;

    if (scrollView.dragging) {
        BOOL shouldHideRandomButton = newContentOffsetY > 0 && newContentOffsetY > self.previousContentOffsetY;
        if (shouldHideRandomButton != self.isRandomButtonHidden) {
            [self setRandomButtonHidden:shouldHideRandomButton animated:YES];
        }
    }

    self.previousContentOffsetY = newContentOffsetY;
}

@end