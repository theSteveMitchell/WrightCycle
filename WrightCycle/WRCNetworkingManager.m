//
//  WRCNetworkingManager.m
//  WrightCycle
//
//  Created by Rob Timpone on 2/14/15.
//  Copyright (c) 2015 Rob Timpone. All rights reserved.
//

#import <Reachability/Reachability.h>
#import "WRCNetworkingManager.h"
#import "WRCStation.h"

@interface WRCNetworkingManager ()

/** The most recent list of stations from the API */
@property (strong, nonatomic) NSArray *cachedStations;

/** The last time a successful data refresh was made */
@property (strong, nonatomic) NSDate *lastRefreshDate;

@end


NSString * const kDivvyStationsJsonFeedUrlString = @"http://www.divvybikes.com/stations/json";

//The Divvy API only updates its JSON feed once a minute
#define SECONDS_TO_WAIT_BEFORE_REFRESHING_DATA 60

@implementation WRCNetworkingManager

#pragma mark - Singleton

+ (instancetype)sharedManager
{
    static WRCNetworkingManager *sharedManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[WRCNetworkingManager alloc] init];
    });
    return sharedManager;
}

#pragma mark - Reachability

+ (BOOL)internetConnectionIsAvailable
{
    Reachability *reachabilty = [Reachability reachabilityForInternetConnection];
    return reachabilty.isReachable;
}

#pragma mark - Divvy API Requests

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
                
                self.lastRefreshDate = [NSDate date];
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

#pragma mark - Cooldown Period

//An API request should only be made if we don't have any data yet or if 60 seconds has elapsed since the last data refresh
- (BOOL)shouldRefreshStations
{
    BOOL thisIsTheFirstRefresh = !self.lastRefreshDate;
    BOOL enoughTimeHasElapsedToRefresh = -[self.lastRefreshDate timeIntervalSinceNow] >= SECONDS_TO_WAIT_BEFORE_REFRESHING_DATA;
    
    return thisIsTheFirstRefresh || enoughTimeHasElapsedToRefresh;
}

#pragma mark - Cached Stations

- (NSArray *)fetchCachedStationsWithIds: (NSArray *)stationIds
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat: @"stationId IN %@", stationIds];
    return [self.cachedStations filteredArrayUsingPredicate: predicate];
}

@end