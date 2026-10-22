#import "PGScreenMap.h"

@implementation PGScreenMap

+ (UIImage *)uprightImage:(UIImage *)image
{
    if(image == nil || image.imageOrientation == UIImageOrientationUp)
    {
        return image;
    }
    UIGraphicsBeginImageContextWithOptions(image.size, YES, image.scale);
    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    UIImage *upright = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return upright ?: image;
}

@end
