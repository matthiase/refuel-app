//
//  PRXMapViewController
//  Refuel
//
//  Created by Matthias Eder on 7/7/13.
//  Copyright (c) 2013 Matthias Eder. All rights reserved.
//

#import "PRXMapViewController.h"
#import "PRXResultsViewController.h"
#import "PRXPreferences.h"
#import "PRXAnnotation.h"
#import "PRXFuelType.h"
#import "MFSideMenuContainerViewController.h"
#import "NRELClient.h"
#import "AFHTTPRequestOperation.h"
#import "WTGlyphFontSet.h"
#import <QuartzCore/QuartzCore.h>
#import "UIColor+Custom.h"

@interface PRXMapViewController () {
    CLLocationManager *locationManager;
    UITextField *activeTextField;
    NSDictionary *defaults;
}
@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (weak, nonatomic) IBOutlet UIButton *refreshButton;
@property (weak, nonatomic) IBOutlet UIButton *listButton;
@property (weak, nonatomic) IBOutlet MKMapView *mapView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;
@property (strong, nonatomic) UITextField *searchTextField;

@property (strong, nonatomic) NSArray *searchResults;
@property (nonatomic) BOOL needsRefresh;

- (void)updateLocation:(id)sender;
- (void)settingsButtonPressed:(id)sender;
- (void)refreshButtonClicked:(id)sender;
@end


@implementation PRXMapViewController

static NSString *const kCurrentLocation = @"";
static NSInteger const kDistanceFilter = 1000;
static double const kDefaultRadiusInMeters = 10000;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {

    }
    return self;
}


- (void)dealloc {
    if (self.isViewLoaded) {
        [[PRXPreferences sharedInstance] removeObserver:self forKeyPath:@"fuels"];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}


- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIBarButtonItem *negativeSeperator = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    negativeSeperator.width = -8;
    
    UIButton *settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [settingsButton setFrame:CGRectMake(0.0, 0.0f, 30.0f, 30.0f)];
    [settingsButton.titleLabel setFont:[UIFont systemFontOfSize:20.0f]];
    [settingsButton setTitleColor:[UIColor rflMediumBlueColor] forState:UIControlStateNormal];
    [settingsButton setTitleColor:[UIColor rflHighlightedBlueColor] forState:UIControlStateHighlighted];
    [settingsButton setGlyphNamed:@"fontawesome##reorder"];
    [settingsButton addTarget:self action:@selector(settingsButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *settingsButtonItem = [[UIBarButtonItem alloc] initWithCustomView:settingsButton];
    
    UIBarButtonItem *spacerLeft = [[UIBarButtonItem alloc]
                                   initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                   target:nil
                                   action:nil];
    
    UIView *spacerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 8)];
    self.searchTextField = [[UITextField alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 240.0f, 31.0f)];
    [self.searchTextField setBorderStyle:UITextBorderStyleNone];
    [self.searchTextField setContentVerticalAlignment: UIControlContentVerticalAlignmentCenter];
    [self.searchTextField setLeftViewMode:UITextFieldViewModeAlways];
    [self.searchTextField setLeftView:spacerView];
    [self.searchTextField setClearButtonMode:UITextFieldViewModeWhileEditing];
    [self.searchTextField setPlaceholder:@"Search"];
    [self.searchTextField.layer setBorderColor:[UIColor rflHighlightedBlueColor].CGColor];
    [self.searchTextField.layer setBorderWidth:1.0f];
    
    [self.searchTextField setDelegate:self];
    
    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithCustomView:self.searchTextField];
    
    UIBarButtonItem *spacerRight = [[UIBarButtonItem alloc]
                                   initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                   target:nil
                                   action:nil];
    
    UIButton *currentLocationButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [currentLocationButton setFrame:CGRectMake(0.0, 0.0f, 30.0f, 30.0f)];    
    [currentLocationButton.titleLabel setFont:[UIFont systemFontOfSize:20.0f]];
    [currentLocationButton setTitleColor:[UIColor rflMediumBlueColor] forState:UIControlStateNormal];
    [currentLocationButton setTitleColor:[UIColor rflHighlightedBlueColor] forState:UIControlStateHighlighted];
    [currentLocationButton setGlyphNamed:@"fontawesome##location-arrow"];
    [currentLocationButton addTarget:self action:@selector(updateLocation:) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *currentLocationButtonItem = [[UIBarButtonItem alloc] initWithCustomView:currentLocationButton];
    
    NSArray *toolbarItems = @[negativeSeperator, settingsButtonItem, spacerLeft, searchItem, spacerRight, currentLocationButtonItem, negativeSeperator];
    [self.toolbar setItems:toolbarItems animated:YES];
    [self.toolbar setTintColor:[UIColor whiteColor]];
    
    [self.refreshButton setAlpha:0.8f];
    [self.refreshButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.refreshButton addTarget:self action:@selector(refreshButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.listButton.titleLabel setFont:[UIFont boldSystemFontOfSize:22.0f]];
    [self.listButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
    [self.listButton setAlpha:0.8f];
    [self.listButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.listButton setGlyphNamed:@"fontawesome##external-link"];
    [self.listButton addTarget:self action:@selector(listButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    
    // Initially, I took the approach of detecting region updates in the MapView delegate's regionDidChangeAnimated
    // method.  However, that method is called multiple times for each gesture, resulting in unnecessary calls to the
    // API. Another way of accomplishing the same thing is to add custom gesture recognizer to this controller and
    // letting them update the MapView's annotations.
    
    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc]
                                             initWithTarget:self
                                             action:@selector(didDragMap:)];
    [panRecognizer setDelegate:self];
    [self.mapView addGestureRecognizer:panRecognizer];
    
    UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc]
                                                 initWithTarget:self
                                                 action:@selector(didPinchMap:)];
    [pinchRecognizer setDelegate:self];
    [self.mapView addGestureRecognizer:pinchRecognizer];
    [self.mapView setDelegate:self];
    
    // Initialize the location manager.
    locationManager = [[CLLocationManager alloc] init];
    [locationManager setDesiredAccuracy:kCLLocationAccuracyHundredMeters];
    [locationManager setDistanceFilter:kDistanceFilter];
    [locationManager setDelegate:self];    
    
    [[PRXPreferences sharedInstance] addObserver:self forKeyPath:@"fuels" options:0 context:nil];
    
    // If the map is visible and has showUserLocation set to YES, it will continue to upgrade in the
    // background and drain the battery.  Disable showUserLocation when goes into background and enable
    // it when the app becomes active again.
    
    [[NSNotificationCenter defaultCenter]addObserver:self
                                            selector:@selector(didEnterBackground:)
                                                name:UIApplicationDidEnterBackgroundNotification
                                              object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // The view may have to be refreshed if the sidebar closes.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sidebarEventNotification:)
                                                 name:MFSideMenuStateNotificationEvent
                                               object:nil];
    
    // A tap recognizer to dismiss the keyboard when the user taps anywhere but a text input field.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                   initWithTarget:self
                                   action:@selector(dismissKeyboard:)];
    [tap setDelegate:self];
    [self.mapView addGestureRecognizer:tap];
    
    // Let's get this party started.
    [self updateLocation:nil];
}


- (void)viewDidLayoutSubviews {
    // TODO: this should only be performed once.
    CALayer *layer = [CALayer layer];
    layer.frame = CGRectMake(0.0f, self.toolbar.bounds.size.height - 1, self.toolbar.bounds.size.width, 1.0f);
    [layer setBackgroundColor:[UIColor lightGrayColor].CGColor];
    [self.toolbar.layer addSublayer:layer];
    
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"presentResultsView"]) {
        PRXResultsViewController *destination = [segue destinationViewController];
        [destination setResults:self.searchResults];
    }
}


- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqual:@"fuels"]) {
        self.needsRefresh = YES;
        /*
        NSUInteger typeOfChange = [change[NSKeyValueChangeKindKey] unsignedIntegerValue];
        NSIndexSet *indexSet = change[NSKeyValueChangeIndexesKey];
        switch (typeOfChange) {
            case NSKeyValueChangeInsertion:
                
                break;
            case NSKeyValueChangeRemoval:
                
                break;
            default:
                break;
        }
        */
    }
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[PRXPreferences sharedInstance]];
    [userDefaults setObject:data forKey:@"preferences"];
    [userDefaults synchronize];    
}


- (void)didDragMap:(UIGestureRecognizer*)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [self.refreshButton setHidden:NO];
    }
}


- (void)didPinchMap:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
       [self.refreshButton setHidden:NO];
    }
}


- (void)dismissKeyboard:(UIGestureRecognizer *)gestureRecognizer {
    if (activeTextField) {
        [activeTextField resignFirstResponder];
    }
}


- (void)didEnterBackground:(NSNotification *)notification {
    if (self.mapView.showsUserLocation) {
        [self.mapView setShowsUserLocation:NO];
    }
}


- (void)didBecomeActive:(NSNotification *)notification {
    // Only show the current location if that was the state the application was in when
    // it went into the background.
    if ([self.searchTextField.text isEqualToString:kCurrentLocation]) {
        [self.mapView setShowsUserLocation:YES];
    }
}


- (void)sidebarEventNotification:(NSNotification *)notification {
    NSUInteger eventType = [[[notification userInfo] objectForKey:@"eventType"] unsignedIntegerValue];
    switch (eventType) {
        case MFSideMenuStateEventMenuWillClose:
            if (self.needsRefresh) {
                [self refreshButtonClicked:nil];
            }
            break;            
        default:
            break;
    }
}


- (void)listButtonPressed:(id)sender {
    [self performSegueWithIdentifier:@"presentResultsView" sender:nil];
}


- (MFSideMenuContainerViewController *)menuContainerViewController {
    return (MFSideMenuContainerViewController *)self.navigationController.parentViewController;
}


- (void)updateLocation:(id)sender {
    [locationManager startUpdatingLocation];
}

- (void)settingsButtonPressed:(id)sender {
    [self.menuContainerViewController toggleLeftSideMenuCompletion:nil];
}

- (void)refreshButtonClicked:(id)sender {
    [self updateAnnotationsForRegion:self.mapView.region];
}


# pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    [self.mapView setShowsUserLocation: YES];
    CLLocation *currentLocation = [locations lastObject];
    self.searchTextField.text = kCurrentLocation;
    [locationManager stopUpdatingLocation];
    [self centerMapOnLocation:currentLocation withRadius:kDefaultRadiusInMeters];
}


- (void)centerMapOnLocation:(CLLocation *)location withRadius:(NSInteger)meters {
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(location.coordinate, meters, meters);
    [self.mapView setRegion:region animated:YES];
    [self updateAnnotationsForRegion:region];
    //[self updateAnnotationsForRegion:self.mapView.region];
}


- (void)updateAnnotationsForRegion:(MKCoordinateRegion)region {
    double factor = ABS(cos(2 * M_PI * region.center.latitude / 360.0));    
    double latitudeDeltaInMiles = region.span.latitudeDelta * 69.0;
    double longitudeDeltaInMiles = region.span.longitudeDelta * 69.0 * factor;
    // TODO: the radius is not always calulated correctly.
    double radiusInMiles = latitudeDeltaInMiles > longitudeDeltaInMiles ? latitudeDeltaInMiles : longitudeDeltaInMiles;
    
    NSLog(@"REQUESTING FUEL STATIONS FROM API\nLATITUDE DELTA: %f\nLONGITUDE DELTA: %f\nRADIUS: %f miles", region.span.latitudeDelta, region.span.longitudeDelta, radiusInMiles);
    
    [self.mapView removeAnnotations:self.mapView.annotations];
    
    NSString *path = @"alt-fuel-stations/v1/nearest.json";
    //float radiusInMiles = kDefaultRadiusInMeters * 0.000621371;
    
    NSDictionary *params = @{@"api_key": @"2cb264fc3ffee5c6aff826a024ffb4fd637e52e0",
                             @"latitude": [NSNumber numberWithFloat:region.center.latitude],
                             @"longitude": [NSNumber numberWithFloat:region.center.longitude],
                             @"radius": [NSNumber numberWithFloat:radiusInMiles],
                             @"fuel_type": [[[PRXPreferences sharedInstance] selectedFuelCodes] componentsJoinedByString:@","],
                             @"status": @"E",
                             @"access": @"public",
                             @"limit": @100
                             };
    
    NSLog(@"Request parameters:\n%@", params);
    
    [[NRELClient sharedClient] getPath:path parameters:params success:^(AFHTTPRequestOperation *operation, id responseObject) {
        self.searchResults = responseObject[@"fuel_stations"] ?: @[ ];
        NSMutableArray *annotations = [[NSMutableArray alloc] initWithCapacity:self.searchResults.count];
        
        NSLog(@"Found %d stations.", self.searchResults.count);
        for (NSDictionary *station in self.searchResults) {
            CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake([station[@"latitude"] floatValue],
                                                                           [station[@"longitude"] floatValue]);
            PRXAnnotation *annotation = [[PRXAnnotation alloc] initWithCoordinate:coordinate title:station[@"station_name"]];
            annotation.subtitle = [NSString stringWithFormat:@"%@, %@, %@",
                                   station[@"street_address"],
                                   station[@"city"],
                                   station[@"state"]];
            [annotations addObject:annotation];
        }
        [self.mapView addAnnotations:annotations];
        [self.refreshButton setHidden:YES];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"API request to %@ failed:\n%@", operation.request.URL, error);
    }];
}


# pragma mark - MKMapViewDelegate methods

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    static NSString *identifier = @"AnnotationIdentifier";    
    MKPinAnnotationView *annotationView = nil;

    if ([annotation isKindOfClass:[PRXAnnotation class]]) {    
        annotationView = (MKPinAnnotationView *) [self.mapView dequeueReusableAnnotationViewWithIdentifier: identifier];
        if (!annotationView) {
            annotationView = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier: identifier];
            annotationView.pinColor = MKPinAnnotationColorRed;
            //annotationView.image=[UIImage imageNamed:@"arrest.png"] ;
            [annotationView setEnabled:YES];
            annotationView.userInteractionEnabled = YES;
            [annotationView setCanShowCallout:YES];        
            UIButton *disclosureButton = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
            annotationView.rightCalloutAccessoryView = disclosureButton;
        }
        else {
            annotationView.annotation = annotation;
        }
    }
    
    return annotationView;
}


/*
- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    MKCoordinateRegion newRegion = self.mapView.region;
    
    // The number of miles spanned by a degree of longitude range varies based on the current latitude.
    // For example, one degree of longitude spans a distance of ~69 miles at the equator but shrinks to 0
    // at the poles. However, unlike longitudinal distances, which vary based on the latitude, one degree
    // of latitude is always ~69 miles (ignoring variations due to the slightly ellipsoidal shape of Earth).
    // Length of 1 degree of Longitude (miles) = cosine (latitude) × 69 (miles).
    
    double latitudeOffsetInDegrees = oldRegion.center.latitude - newRegion.center.latitude;
    double longitudeOffsetInDegrees = oldRegion.center.longitude - newRegion.center.longitude;
    double factor = ABS(cos(2 * M_PI * newRegion.center.latitude / 360.0));
    
    double latitudeOffsetInMiles = latitudeOffsetInDegrees * 69.0;
    double longitudeOffsetInMiles = longitudeOffsetInDegrees * 69.0 * factor;
    
    NSLog(@"LONGITUDE CHANGE: %fd\nLONGITUDE CHANGE: %fd", latitudeOffsetInMiles, longitudeOffsetInMiles);

    oldRegion = newRegion;
}
*/


# pragma mark - UITextFieldDelegate methods

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    NSLog(@"Search field became active.");
    activeTextField = textField;
    if (activeTextField == self.searchTextField && [activeTextField.text isEqualToString:kCurrentLocation]) {
        activeTextField.text = @"";
        [activeTextField becomeFirstResponder];
    }
}


- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.mapView setShowsUserLocation:NO];
    [textField resignFirstResponder];
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder geocodeAddressString:textField.text completionHandler:^(NSArray *placemarks, NSError *error) {
        CLPlacemark *placemark = [placemarks objectAtIndex:0];
        [self centerMapOnLocation:placemark.location withRadius:kDefaultRadiusInMeters];
    }];
    return YES;
}

@end
