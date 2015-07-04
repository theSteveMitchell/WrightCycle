//
//  WRCNetworkingManager.m
//  WrightCycle
//
//  Created by Rob Timpone on 2/14/15.
//  Copyright (c) 2015 Rob Timpone. All rights reserved.
//

@import CloudKit;

#import "WRCConfiguration.h"
#import "WRCNetworkingManager.h"
#import "WRCStation.h"

@interface WRCNetworkingManager ()

/** The most recent list of stations from the API */
@property (strong, nonatomic) NSArray *cachedStations;

/** The last time a successful data refresh was made */
@property (strong, nonatomic) NSDate *lastStationsRefreshDate;

/** The most recently retrieved configuration object */
@property (strong, nonatomic, readwrite) WRCConfiguration *cachedConfiguration;

/** The last time a successful configuration refresh was made */
@property (strong, nonatomic) NSDate *lastConfigurationRefreshDate;

@end

NSString * const kConfigurationUpdatedNotification = @"kConfigurationUpdatedNotification";
NSString * const kDivvyStationsJsonFeedUrlString = @"http://www.divvybikes.com/stations/json";

//The Divvy API only updates its JSON feed once a minute
#define SECONDS_TO_WAIT_BEFORE_REFRESHING_STATION_DATA 60
#define SECONDS_TO_WAIT_BEFORE_REFRESHING_CONFIGURATION 15 * 60

@implementation WRCNetworkingManager

#pragma mark - Divvy API

- (NSArray *)getStationsListWithSuccess: (void (^)(NSArray *stations))success failure: (void (^)(NSError *error))failure
{
    return [self getStationsListImmediately: NO withSuccess: success failure: failure];
}

- (NSArray *)getStationsListImmediately: (BOOL)shouldMakeRequestImmediately withSuccess: (void (^)(NSArray *stations))success failure: (void (^)(NSError *error))failure
{
    if ([self shouldRefreshStations] || shouldMakeRequestImmediately)
    {
        NSURL *url = [NSURL URLWithString: kDivvyStationsJsonFeedUrlString];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL: url completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
            
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible: NO];
            
            if (error && failure)
            {
                failure(error);
            }
            else
            {
                //extract the array of station dictionaries from the API response
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
                NSArray *stationDictionaries = json[@"stationBeanList"];
                
                //convert the dictionaries into station objects
                NSMutableArray *stations = [[NSMutableArray alloc] init];
                for (NSDictionary *stationDictionary in stationDictionaries)
                {
                    WRCStation *station = [WRCStation stationFromDictionary: stationDictionary];
                    [stations addObject: station];
                }
                
                self.lastStationsRefreshDate = [NSDate date];
                self.cachedStations = stations;
                
                success(stations);
            }
        }];
        
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible: YES];
        [task resume];
    }
    
    //return the currently cached list of stations immediately
    return self.cachedStations;
}

#pragma mark - CloudKit

- (void)getAppConfigurationWithSuccess: (void (^)(WRCConfiguration *configuration))success failure: (void (^)(NSError *error))failure
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible: YES];
    
    CKDatabase *publicCloudDatabase = [[CKContainer defaultContainer] publicCloudDatabase];
    NSPredicate *truePredicate = [NSPredicate predicateWithFormat: @"TRUEPREDICATE"];
    CKQuery *query = [[CKQuery alloc] initWithRecordType: @"configuration" predicate: truePredicate];
    [publicCloudDatabase performQuery: query inZoneWithID: nil completionHandler: ^(NSArray *results, NSError *error) {
        
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible: NO];
        
        if (error)
        {
            failure(error);
        }
        else
        {
            CKRecord *record = [results firstObject];
            WRCConfiguration *configuration = [WRCConfiguration configurationFromRecord: record];
            
            if (![self.cachedConfiguration isEqualToConfiguration: configuration])
            {
                self.cachedConfiguration = configuration;
            }

            self.lastConfigurationRefreshDate = [NSDate date];
            success(configuration);
        }
    }];
}

#pragma mark - Cooldown Period

//An API request should only be made if we don't have any data yet or if 60 seconds has elapsed since the last data refresh
- (BOOL)shouldRefreshStations
{
    BOOL thisIsTheFirstRefresh = !self.lastStationsRefreshDate;
    BOOL enoughTimeHasElapsedToRefresh = -[self.lastStationsRefreshDate timeIntervalSinceNow] >= SECONDS_TO_WAIT_BEFORE_REFRESHING_STATION_DATA;
    
    return thisIsTheFirstRefresh || enoughTimeHasElapsedToRefresh;
}

//A configuration refresh should only be made if at least 15 minutes have passed since the last refresh attempt
- (BOOL)isReadyForConfigurationRefresh
{
    BOOL thisIsTheFirstRefresh = !self.lastConfigurationRefreshDate;
    BOOL enoughTimeHasElapsedToRefresh = -[self.lastConfigurationRefreshDate timeIntervalSinceNow] >= SECONDS_TO_WAIT_BEFORE_REFRESHING_CONFIGURATION;
    
    return thisIsTheFirstRefresh || enoughTimeHasElapsedToRefresh;
}

#pragma mark - Cached Stations

- (NSArray *)fetchCachedStationsWithIds: (NSArray *)stationIds
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat: @"stationId IN %@", stationIds];
    return [self.cachedStations filteredArrayUsingPredicate: predicate];
}

#pragma mark - Setters

//Post a notification when the configuration is updated
- (void)setCachedConfiguration:(WRCConfiguration *)cachedConfiguration
{
    _cachedConfiguration = cachedConfiguration;
    [[NSNotificationCenter defaultCenter] postNotificationName: kConfigurationUpdatedNotification object: cachedConfiguration];
}

@end
