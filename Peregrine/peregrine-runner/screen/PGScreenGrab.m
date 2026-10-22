#import "PGScreenGrab.h"
#import "PGScreenMap.h"

@implementation PGScreenGrab

+ (uint64_t)hashGray:(const uint8_t *)bytes width:(NSInteger)width height:(NSInteger)height
{
    if(bytes == NULL || width <= 0 || height <= 0)
    {
        return 0;
    }
    uint64_t hash = 1469598103934665603ULL;
    for(NSInteger y = 0; y < height; y += 32)
    {
        const uint8_t *row = bytes + y * width;
        for(NSInteger x = 0; x < width; x += 32)
        {
            hash ^= row[x];
            hash *= 1099511628211ULL;
        }
    }
    hash ^= (uint64_t)width;
    hash *= 1099511628211ULL;
    hash ^= (uint64_t)height;
    return hash;
}

+ (NSData *)grayDataFromApplication:(XCUIApplication *)application width:(NSInteger *)width height:(NSInteger *)height
{
    return [self grayDataFromImage:[self uprightScreenshotOfApplication:application] width:width height:height];
}

+ (UIImage *)uprightScreenshotOfApplication:(XCUIApplication *)application
{
    XCUIScreenshot *shot = [application screenshot];
    return [PGScreenMap uprightImage:[UIImage imageWithData:shot.PNGRepresentation]];
}

+ (NSData *)grayDataFromImage:(UIImage *)image width:(NSInteger *)width height:(NSInteger *)height
{
    if(width != nil)
    {
        *width = 0;
    }
    if(height != nil)
    {
        *height = 0;
    }
    CGImageRef cgImage = image.CGImage;
    size_t pixelWidth = cgImage == NULL ? 0 : CGImageGetWidth(cgImage);
    size_t pixelHeight = cgImage == NULL ? 0 : CGImageGetHeight(cgImage);
    if(pixelWidth == 0 || pixelHeight == 0)
    {
        return nil;
    }
    NSMutableData *gray = [NSMutableData dataWithLength:pixelWidth * pixelHeight];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(gray.mutableBytes, pixelWidth, pixelHeight, 8, pixelWidth, space, (CGBitmapInfo)kCGImageAlphaNone);
    CGContextDrawImage(context, CGRectMake(0, 0, pixelWidth, pixelHeight), cgImage);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    if(width != nil)
    {
        *width = (NSInteger)pixelWidth;
    }
    if(height != nil)
    {
        *height = (NSInteger)pixelHeight;
    }
    return gray;
}

+ (NSArray<PGElementNode *> *)nodesFromGray:(const uint8_t *)gray
                                      width:(NSInteger)width
                                     height:(NSInteger)height
                               segmentation:(PGSegmentation *)segmentation
{
    if(gray == NULL || width <= 0 || height <= 0)
    {
        return @[];
    }
    return [segmentation nodesFromGray:gray width:width height:height];
}

+ (NSArray<PGElementNode *> *)nodesFromScreenshot:(XCUIApplication *)application segmentation:(PGSegmentation *)segmentation
{
    NSInteger width = 0;
    NSInteger height = 0;
    NSData *gray = [self grayDataFromApplication:application width:&width height:&height];
    return [self nodesFromGray:gray.bytes width:width height:height segmentation:segmentation];
}

+ (PGOperate *)scaleOperate:(PGOperate *)operate fromPixels:(CGSize)pixels toScreen:(CGSize)points
{
    if(operate == nil || points.width <= 0 || points.height <= 0 || pixels.width < 1 || pixels.height < 1)
    {
        return operate;
    }
    CGFloat pixelWidth = pixels.width;
    CGFloat pixelHeight = pixels.height;
    PGElementRect rect = operate.rect;
    rect.left = (NSInteger)(rect.left * points.width / pixelWidth);
    rect.top = (NSInteger)(rect.top * points.height / pixelHeight);
    rect.width = (NSInteger)(rect.width * points.width / pixelWidth);
    rect.height = (NSInteger)(rect.height * points.height / pixelHeight);
    operate.rect = rect;
    if(operate.path.count > 0)
    {
        NSMutableArray<NSDictionary *> *path = [NSMutableArray arrayWithCapacity:operate.path.count];
        for(NSDictionary *point in operate.path)
        {
            if(![point isKindOfClass:[NSDictionary class]])
            {
                continue;
            }
            [path addObject:@{
                @"x": @([point[@"x"] doubleValue] * points.width / pixelWidth),
                @"y": @([point[@"y"] doubleValue] * points.height / pixelHeight)
            }];
        }
        operate.path = path;
    }
    return operate;
}

@end
