#import "PGExploreStrategy.h"

@implementation PGExploreStrategy

+ (double)learningRateForObservations:(NSInteger)observations
{
    double rate = observations < 20001 ? 0.5 : 0.4;
    if(observations > 50000)
    {
        rate -= 0.1;
    }
    if(observations > 100000)
    {
        rate -= 0.1;
    }
    if(observations > 250000)
    {
        rate -= 0.1;
    }
    return rate < 0.25 ? 0.25 : rate;
}

@end
