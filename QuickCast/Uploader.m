//
//  QuickCast
//
//  Copyright (c) 2013 Pete Nelson, Neil Kinnish, Dom Murphy
//

#import "Uploader.h"
#import "AmazonS3Client.h"
#import "AppDelegate.h"
#import "QuickcastAPI.h"
#import "S3TransferManager.h"


@implementation Uploader{
    
    NSInteger filesize;
    NSString *videoLength;
    NSString *videoWidth;
    NSString *videoHeight;
    NSString *castId;
    
}


-(void)request:(AmazonServiceRequest *)request didReceiveResponse:(NSURLResponse *)aResponse{
    //NSLog(@"didReceiveResponse");
    
}

-(void)request:(AmazonServiceRequest *)request didCompleteWithResponse:(AmazonServiceResponse *)aResponse{
    
    QuickcastAPI *api = [[QuickcastAPI alloc] init];
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSString *token = [prefs objectForKey:@"token"];
     
    NSDictionary *params = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:token,castId, nil] forKeys:[NSArray arrayWithObjects:@"token",@"castid", nil]];
    
    [api castEncode:params completionHandler:^(NSDictionary *response, NSError *error, NSHTTPURLResponse * httpResponse) {
        
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                
                NSLog(@"Error: %@",error.description);
                
            });
            
            
        }
        else{
            
            //check http status
            if (httpResponse.statusCode == 200) {
                
                //call app delegate on the main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    NSLog(@"Encoding");
                    
                    
                });
                
            }
            else{
                dispatch_async(dispatch_get_main_queue(), ^{
                   
                    NSLog(@"Error: %ld",(long)httpResponse.statusCode);
                   
                });
                
            }
        }
        
    }];
    

    dispatch_async(dispatch_get_main_queue(),^ {
        
        AppDelegate *app = (AppDelegate *)[NSApp delegate];
        app.recordItem.title = @"Record";
        [app.recordItem setEnabled:YES];
        
        NSString *videoFilesize = [NSString stringWithFormat:@"%ld",(long)filesize];
        
        [app.statusItem setTitle:@""];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"CompletedUploading" object:self];
        [app complete:castId filesize:videoFilesize length:videoLength width:videoWidth height:videoHeight];
        
    } );
    
    aResponse.request = request;
}

-(void)request:(AmazonServiceRequest *)request didReceiveData:(NSData *)data{
    NSLog(@"didReceiveData");
    
}

-(void)request:(AmazonServiceRequest *)request didSendData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite{
    
    //NSLog(@"didSendData %ld %ld",totalBytesWritten,(long)totalBytesExpectedToWrite);
    dispatch_async(dispatch_get_main_queue(),^ {
        
        AppDelegate *app = (AppDelegate *)[NSApp delegate];
        
        long double percentage = ((long double)totalBytesWritten/(long double)totalBytesExpectedToWrite)*100;
        NSString *perc = [NSString stringWithFormat:@"%.0Lf%%",percentage];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"Uploading" object:self];
        [app.statusItem setTitle:perc];
    
    } );
    
    
}

-(void)request:(AmazonServiceRequest *)request didFailWithError:(NSError *)theError{
    
    NSLog(@"didFailWithError %@",theError.description);
    dispatch_async(dispatch_get_main_queue(),^ {
        
        
        
        AppDelegate *app = (AppDelegate *)[NSApp delegate];
        app.recordItem.title = @"Record";
        [app.recordItem setEnabled:YES];
        [app.statusItem setTitle:@""];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"FailedUploading" object:self];
    } );
    
}

-(void)request:(AmazonServiceRequest *)request didFailWithServiceException:(NSException *)theException{
    
    NSLog(@"didFailWithServiceException %@",theException.description);
    dispatch_async(dispatch_get_main_queue(),^ {
        
        
        AppDelegate *app = (AppDelegate *)[NSApp delegate];
        app.recordItem.title = @"Record";
        [app.recordItem setEnabled:YES];
        [app.statusItem setTitle:@""];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"FailedUploading" object:self];
        
    } );
    
}


- (void)performUpload:(NSString *)filename video:(NSURL *)videoUrl thumbnail:(NSURL *)thumbnailUrl details:(NSDictionary *)details  length:(NSString *)length width:(NSString *)width height:(NSString *)height{
    
    //get the params ready
    NSString *rawBucket = [details objectForKey:@"bucket-1"];
    NSString *bucket = [details objectForKey:@"bucket-2"];
    
    NSNumber *cid = [[details objectForKey:@"cast"] objectForKey:@"addcast"];
    
    castId = [cid stringValue];
    videoLength =  length;
    videoWidth = width;
    videoHeight = height;
    
    NSNumber *uid = [[details objectForKey:@"user"] objectForKey:@"userid"];
    
    NSDictionary *creds = [[details objectForKey:@"federationToken"] objectForKey:@"Credentials"];
    NSString *userId = [uid stringValue];
    
    //now upload to Amazon
    AmazonCredentials *credentials = [[AmazonCredentials alloc] initWithAccessKey:[creds objectForKey:@"AccessKeyId"] withSecretKey:[creds objectForKey:@"SecretAccessKey"] withSecurityToken:[creds objectForKey:@"SessionToken"] ];
    
    AppDelegate *app = (AppDelegate *)[NSApp delegate];
    
    // TransferManager
    app.transferManager = [[S3TransferManager alloc] init];
    AmazonS3Client *s3 = [[AmazonS3Client alloc] initWithCredentials:credentials];
    
    
    
    /////////////// Do the thumbnail and gif first as very small and fast
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        // If we have got a gif
        if([[NSFileManager defaultManager] fileExistsAtPath:[[videoUrl.path stringByDeletingPathExtension] stringByAppendingPathExtension:@"gif"]]){
            
            NSString *relativePathGif = [NSString stringWithFormat:@"%@/%@/%@",userId,castId,@"quickcast.gif"];
            
            S3PutObjectRequest *porGif = [[S3PutObjectRequest alloc] initWithKey:relativePathGif inBucket:bucket];
            
            porGif.data  = [NSData dataWithContentsOfFile:[[videoUrl.path stringByDeletingPathExtension] stringByAppendingPathExtension:@"gif"]];
            porGif.contentType = @"image/gif";
            
            //porGif.expires = 2147483647; //max int value
            porGif.cannedACL = [S3CannedACL publicRead];
            
            //porThumb.delegate = self;
            //just do syncronously so only video uses the async callbacks
            [s3 putObject:porGif];
            //[app.transferManager synchronouslyUpload:porGif];
            
        }
        
        if(thumbnailUrl != nil){
            
            NSString *relativePathThumb = [NSString stringWithFormat:@"%@/%@/%@",userId,castId,@"quickcast.jpg"];
            
            S3PutObjectRequest *porThumb = [[S3PutObjectRequest alloc] initWithKey:relativePathThumb inBucket:bucket];
            
            porThumb.data  = [NSData dataWithContentsOfFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"quickcast_thumb.jpg"]];
            //por.contentType = [Utilities MIMETypeForExtension:[theURL.path pathExtension]];
            
            //porThumb.expires = 2147483647; //max int value
            porThumb.cannedACL = [S3CannedACL publicRead];
            porThumb.contentType = @"image/jpeg";
            //porThumb.delegate = self;
            //just do syncronously so only video uses the async callbacks
            [s3 putObject:porThumb];
            //[app.transferManager upload:porThumb];
        }
    });

    ///////////////
    
    [app.transferManager setS3:s3];
    
    NSString *relativePath = [NSString stringWithFormat:@"%@/%@/%@",userId,castId,@"quickcast.mp4"];
    
    S3PutObjectRequest *por = [[S3PutObjectRequest alloc] initWithKey:relativePath inBucket:rawBucket];
    //harde code here videoUrl =[NSURL fileURLWithPath: @"/Users/petenelson/Movies/QuickCast/quickcast-27-09-2013-02-54-50.mp4"];
    por.data  = [NSData dataWithContentsOfURL:videoUrl];
   
    //por.expires = 2147483647; //max int value
    por.cannedACL = [S3CannedACL publicRead];
    [app.transferManager setDelegate:self];
    [app.transferManager upload:por];
    
        
}

- (void) dealloc{

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
}


@end
