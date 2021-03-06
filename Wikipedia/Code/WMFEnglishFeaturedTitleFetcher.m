
#import "WMFEnglishFeaturedTitleFetcher.h"
#import "Wikipedia-Swift.h"

#import "AFHTTPSessionManager+WMFDesktopRetry.h"
#import "AFHTTPSessionManager+WMFConfig.h"
#import "WMFApiJsonResponseSerializer.h"
#import "WMFMantleJSONResponseSerializer.h"
#import "WMFNetworkUtilities.h"
#import "MWKSearchResult.h"
#import "NSDictionary+WMFCommonParams.h"
#import "WMFBaseRequestSerializer.h"

NS_ASSUME_NONNULL_BEGIN

@interface WMFEnglishFeaturedTitleRequestSerializer : WMFBaseRequestSerializer
@end

@interface WMFEnglishFeaturedTitleResponseSerializer : WMFApiJsonResponseSerializer
@end

@interface WMFTitlePreviewRequestSerializer : WMFBaseRequestSerializer
@end

@interface WMFEnglishFeaturedTitleFetcher ()
@property (nonatomic, strong) AFHTTPSessionManager* featuredTitleOperationManager;
@property (nonatomic, strong) AFHTTPSessionManager* titlePreviewOperationManager;
@end

@implementation WMFEnglishFeaturedTitleFetcher

+ (AFHTTPSessionManager*)featuredTitleOperationManager {
    AFHTTPSessionManager* featuredTitleOperationManager = [AFHTTPSessionManager wmf_createDefaultManager];
    featuredTitleOperationManager.requestSerializer  = [WMFEnglishFeaturedTitleRequestSerializer serializer];
    featuredTitleOperationManager.responseSerializer = [WMFEnglishFeaturedTitleResponseSerializer serializer];
    return featuredTitleOperationManager;
}

+ (AFHTTPSessionManager*)titlePreviewOperationManager {
    AFHTTPSessionManager* titlePreviewOperationManager = [AFHTTPSessionManager wmf_createDefaultManager];
    titlePreviewOperationManager.requestSerializer  = [WMFTitlePreviewRequestSerializer serializer];
    titlePreviewOperationManager.responseSerializer =
        [WMFMantleJSONResponseSerializer serializerForValuesInDictionaryOfType:[MWKSearchResult class] fromKeypath:@"query.pages"];
    return titlePreviewOperationManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.featuredTitleOperationManager = [WMFEnglishFeaturedTitleFetcher featuredTitleOperationManager];
        self.titlePreviewOperationManager  = [WMFEnglishFeaturedTitleFetcher titlePreviewOperationManager];
    }
    return self;
}

- (BOOL)isFetching {
    return [[self.featuredTitleOperationManager operationQueue] operationCount] > 0 || [[self.titlePreviewOperationManager operationQueue] operationCount] > 0;
}

- (AnyPromise*)fetchFeaturedArticlePreviewForDate:(NSDate*)date {
    @weakify(self);
    NSURL* siteURL = [NSURL wmf_URLWithDefaultSiteAndlanguage:@"en"];
    return [self.featuredTitleOperationManager wmf_GETAndRetryWithURL:siteURL parameters:date]
           .thenInBackground(^(NSString* title) {
        @strongify(self);
        if (!self) {
            return [AnyPromise promiseWithValue:[NSError cancelledError]];
        }
        return [self.titlePreviewOperationManager wmf_GETAndRetryWithURL:siteURL parameters:title]
        .then(^(NSArray<MWKSearchResult*>* featuredTitlePreviews) {
            return featuredTitlePreviews.firstObject;
        });
    });
}

@end

@implementation WMFEnglishFeaturedTitleRequestSerializer

+ (NSDateFormatter*)featuredArticleDateFormatter {
    static NSDateFormatter* feedItemDateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        feedItemDateFormatter = [[NSDateFormatter alloc] init];
        feedItemDateFormatter.dateFormat = @"MMMM d, YYYY";
        // feed format uses US dates—specifically month names
        feedItemDateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en-US"];
    });
    return feedItemDateFormatter;
}

+ (NSString*)titleForDate:(NSDate*)date {
    static NSString* tfaTitleTemplatePrefix = @"Template:TFA_title";
    return [@[tfaTitleTemplatePrefix,
              @"/",
              [[self featuredArticleDateFormatter] stringFromDate:date]] componentsJoinedByString : @""];
}

- (nullable NSURLRequest*)requestBySerializingRequest:(NSURLRequest*)request
                                       withParameters:(nullable id)parameters
                                                error:(NSError* __autoreleasing _Nullable*)error {
    NSDate* date = parameters;
    NSParameterAssert(!date || [date isKindOfClass:[NSDate class]]);
    return [super requestBySerializingRequest:request withParameters:@{
                @"action": @"query",
                @"format": @"json",
                @"titles": [WMFEnglishFeaturedTitleRequestSerializer titleForDate:date],
                // extracts
                @"prop": @"extracts",
                @"exchars": @100,
                @"explaintext": @""
            } error:error];
}

@end

@implementation WMFEnglishFeaturedTitleResponseSerializer

+ (nullable NSString*)titleFromFeedItemExtract:(nullable NSString*)extract {
    if ([extract hasSuffix:@"..."]) {
        /*
           HAX: TextExtracts extension will (sometimes) add "..." to the extract.  In this particular case, we don't
           want it, so we remove it if present.
         */
        return [extract wmf_safeSubstringToIndex:extract.length - 3];
    }
    return extract;
}

- (nullable id)responseObjectForResponse:(nullable NSURLResponse*)response
                                    data:(nullable NSData*)data
                                   error:(NSError* __autoreleasing _Nullable*)outError {
    id json = [super responseObjectForResponse:response data:data error:outError];
    if (!json) {
        return nil;
    }
    NSDictionary* feedItemPageObj = [[json[@"query"][@"pages"] allValues] firstObject];
    NSString* title               =
        [WMFEnglishFeaturedTitleResponseSerializer titleFromFeedItemExtract:feedItemPageObj[@"extract"]];

    if (title.length == 0) {
        DDLogError(@"Empty extract for feed item request %@", response.URL);
        NSError* error = [NSError wmf_errorWithType:WMFErrorTypeStringLength userInfo:@{
                              NSURLErrorFailingURLErrorKey: response.URL
                          }];
        WMFSafeAssign(outError, error);
        return nil;
    }

    return title;
}

@end

@implementation WMFTitlePreviewRequestSerializer

- (nullable NSURLRequest*)requestBySerializingRequest:(NSURLRequest*)request
                                       withParameters:(nullable id)parameters
                                                error:(NSError* __autoreleasing _Nullable*)error {
    NSString* title = parameters;
    NSParameterAssert([title isKindOfClass:[NSString class]] && title.length);
    NSMutableDictionary* baseParams = [NSMutableDictionary wmf_titlePreviewRequestParameters];
    baseParams[@"titles"] = title;
    return [super requestBySerializingRequest:request withParameters:baseParams error:error];
}

@end

NS_ASSUME_NONNULL_END
