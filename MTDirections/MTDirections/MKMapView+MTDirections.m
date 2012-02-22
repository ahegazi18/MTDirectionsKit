#import "MKMapView+MTDirections.h"
#import "MTWaypoint.h"
#import "MTManeuver.h"
#import "MTDirectionsRequest.h"
#import "MTDirectionsOverlay.h"
#import "MTDirectionsOverlayView.h"
#import <objc/runtime.h>

static char overlayKey;
static char displayKey;
static char requestKey;
static char maneuverIndexKey;

@interface MKMapView ()

@property (nonatomic, strong, setter = mt_setRequest:) MTDirectionsRequest *mt_request;
@property (nonatomic, assign, setter = mt_setActiveManeuverIndex:) NSUInteger mt_activeManeuverIndex;

- (void)mt_updateUIForDirectionsDisplayType:(MTDirectionsDisplayType)displayType;
- (void)mt_showManeuverStartingFromIndex:(NSUInteger)maneuverStartIndex;
- (void)mt_setRegionFromWaypoints:(NSArray *)waypoints animated:(BOOL)animated;

@end

@implementation MKMapView (MTDirections)

////////////////////////////////////////////////////////////////////////
#pragma mark - Region
////////////////////////////////////////////////////////////////////////

- (void)setRegionToShowDirectionsAnimated:(BOOL)animated {
    [self mt_setRegionFromWaypoints:self.directionsOverlay.waypoints animated:animated];
}

- (void)mt_setRegionFromWaypoints:(NSArray *)waypoints animated:(BOOL)animated {
    if (waypoints != nil) {
        CLLocationDegrees maxLat = -90.f;
        CLLocationDegrees maxLon = -180.f;
        CLLocationDegrees minLat = 90.f;
        CLLocationDegrees minLon = 180.f;
        MKCoordinateRegion region;
        
        for (NSUInteger i=0; i<waypoints.count; i++) {
            MTWaypoint *currentLocation = [waypoints objectAtIndex:i];
            
            if (currentLocation.coordinate.latitude > maxLat) {
                maxLat = currentLocation.coordinate.latitude;
            }
            if (currentLocation.coordinate.latitude < minLat) {
                minLat = currentLocation.coordinate.latitude;
            }
            if (currentLocation.coordinate.longitude > maxLon) {
                maxLon = currentLocation.coordinate.longitude;
            }
            if (currentLocation.coordinate.longitude < minLon) {
                minLon = currentLocation.coordinate.longitude;
            }
        }
        
        region.center.latitude = (maxLat + minLat) / 2.f;
        region.center.longitude = (maxLon + minLon) / 2.f;
        region.span.latitudeDelta = maxLat - minLat;
        region.span.longitudeDelta = maxLon - minLon;
        
        [self setRegion:region animated:animated];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Directions
////////////////////////////////////////////////////////////////////////

- (MKOverlayView *)viewForDirectionsOverlay:(id<MKOverlay>)overlay {
    // don't display anything if display type is set to none
    if (self.directionsDisplayType == MTDirectionsDisplayTypeNone) {
        return nil;
    }
    
    MTDirectionsOverlay *directionsOverlay = self.directionsOverlay;
    
    if (![overlay isKindOfClass:[MTDirectionsOverlay class]] || directionsOverlay == nil) {
        return nil;
    }
    
    MTDirectionsOverlayView *overlayView = [[MTDirectionsOverlayView alloc] initWithOverlay:directionsOverlay];
	
    return overlayView;
}

- (void)loadDirectionsFrom:(CLLocationCoordinate2D)fromCoordinate
                        to:(CLLocationCoordinate2D)toCoordinate
                 routeType:(MTDirectionsRouteType)routeType
      zoomToShowDirections:(BOOL)zoomToShowDirections {
    __unsafe_unretained MKMapView *blockSelf = self;
    
    [self.mt_request cancel];
    self.mt_request = [MTDirectionsRequest requestFrom:fromCoordinate
                                                    to:toCoordinate
                                             routeType:routeType
                                            completion:^(MTDirectionsOverlay *overlay) {
                                                blockSelf.directionsDisplayType = MTDirectionsDisplayTypeOverview;
                                                blockSelf.directionsOverlay = overlay;
                                                
                                                // If we found at least one waypoint (start and end are always contained)
                                                // zoom the mapView to show the whole direction
                                                if (zoomToShowDirections && overlay.waypoints.count > 2) {
                                                    [blockSelf setRegionToShowDirectionsAnimated:YES];
                                                }
                                            }];
    
    [self.mt_request start];
}

- (void)cancelLoadOfDirections {
    [self.mt_request cancel];
    self.mt_request = nil;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Maneuvers
////////////////////////////////////////////////////////////////////////

- (void)mt_updateUIForDirectionsDisplayType:(MTDirectionsDisplayType)displayType {
    MTDirectionsDisplayType oldDisplayType = self.directionsDisplayType;
    
    if (oldDisplayType != displayType) {
        switch (displayType) {    
            case MTDirectionsDisplayTypeOverview: {
                
            }
                
            case MTDirectionsDisplayTypeDetailedManeuvers: {
                self.mt_activeManeuverIndex = 0;
                [self mt_showManeuverStartingFromIndex:0];
                break;
            }
                
            case MTDirectionsDisplayTypeNone: 
            default: {
                NSArray *overlays = self.overlays;
                
                // re-draw overlays
                [self removeOverlays:overlays];
                [self addOverlays:overlays];
                break;
            }
        }
    }
}

- (BOOL)showNextManeuver {
    NSUInteger activeManeuverIndex = self.mt_activeManeuverIndex;
    
    if (activeManeuverIndex >= self.directionsOverlay.maneuvers.count - 1) {
        return NO;
    }
    
    if (self.directionsDisplayType != MTDirectionsDisplayTypeDetailedManeuvers) {
        self.directionsDisplayType = MTDirectionsDisplayTypeDetailedManeuvers;
        return YES;
    }
    
    activeManeuverIndex++;
    self.mt_activeManeuverIndex = activeManeuverIndex;
    [self mt_showManeuverStartingFromIndex:activeManeuverIndex];
    
    return YES;
}

- (BOOL)showPreviousManeuver {
    NSUInteger activeManeuverIndex = self.mt_activeManeuverIndex;
    
    if (activeManeuverIndex == 0) {
        return NO;
    }
    
    activeManeuverIndex--;
    self.mt_activeManeuverIndex = activeManeuverIndex;
    [self mt_showManeuverStartingFromIndex:activeManeuverIndex];
    
    return YES;
}

- (void)mt_showManeuverStartingFromIndex:(NSUInteger)maneuverStartIndex {
    NSUInteger maneuverEndIndex = maneuverStartIndex + 1;
    
    if (maneuverEndIndex < self.directionsOverlay.maneuvers.count) {
        MTManeuver *startManeuver = [self.directionsOverlay.maneuvers objectAtIndex:maneuverStartIndex];
        MTManeuver *endManeuver = [self.directionsOverlay.maneuvers objectAtIndex:maneuverEndIndex];
        NSArray *waypoints = [NSArray arrayWithObjects:startManeuver.waypoint, endManeuver.waypoint, nil];
        
        [self mt_setRegionFromWaypoints:waypoints animated:YES];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Properties
////////////////////////////////////////////////////////////////////////

- (void)setDirectionsOverlay:(MTDirectionsOverlay *)directionsOverlay {
    MTDirectionsOverlay *overlay = self.directionsOverlay;
    
    // remove old overlay and annotations
    if (overlay != nil) {
        [self removeOverlay:overlay];
    }
    
    // add new overlay
    if (directionsOverlay != nil) {
        [self addOverlay:directionsOverlay];
    }
    
    objc_setAssociatedObject(self, &overlayKey, directionsOverlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (MTDirectionsOverlay *)directionsOverlay {
    return objc_getAssociatedObject(self, &overlayKey);
}

- (void)setDirectionsDisplayType:(MTDirectionsDisplayType)directionsDisplayType {
    // we first update the UI to have access to the old display type here
    [self mt_updateUIForDirectionsDisplayType:directionsDisplayType];
    
    objc_setAssociatedObject(self, &displayKey, [NSNumber numberWithInt:directionsDisplayType], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (MTDirectionsDisplayType)directionsDisplayType {
    return (MTDirectionsDisplayType)[objc_getAssociatedObject(self, &displayKey) intValue];
}

- (void)mt_setRequest:(MTDirectionsRequest *)mt_request {
    objc_setAssociatedObject(self, &requestKey, mt_request, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (MTDirectionsRequest *)mt_request {
    return objc_getAssociatedObject(self, &requestKey);
}

- (void)mt_setActiveManeuverIndex:(NSUInteger)mt_activeManeuverIndex {
    objc_setAssociatedObject(self, &maneuverIndexKey, [NSNumber numberWithInt:mt_activeManeuverIndex], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSUInteger)mt_activeManeuverIndex {
    return [objc_getAssociatedObject(self, &maneuverIndexKey) intValue];
}

@end
