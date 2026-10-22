#import "PGSegmentation.h"

static const NSInteger PGDialogEdgeInkPercent = 6;
// Screen width over this is the widest blank run kept inside a segment: about 6 pt on a phone.
static const NSInteger PGColumnBridgeDivisor = 60;
static const NSInteger PGSegmentMinPixels = 8;
// Screenshots are in pixels; size classes are judged in points of a phone this wide.
static const double PGPhoneWidthPoints = 390.0;
static const double PGImageCellPoints = 8.0;
static const double PGImageMinSidePoints = 40.0;
static const NSInteger PGImageFillPercent = 70;
// A flat card or banner has one dominant shade; a photo spreads over many.
static const NSInteger PGImageDominantPercent = 50;
static const NSInteger PGImageCoverPercent = 60;
// Photo cells keep sensor noise and gradients; flat fills stay within a few shades.
static const NSInteger PGImageCellRange = 10;
static const NSInteger PGImageTexturedPercent = 25;
// Neighbouring photo cells shade into each other; a sheet or card over a photo starts with a jump.
static const int PGImageNeighbourJump = 40;

@implementation PGSegment
@end

@implementation PGSegmentation
{
    double _pixelsPerPoint;
}

- (NSArray<PGSegment *> *)segmentsFromGray:(const uint8_t *)pixels
                                     width:(NSInteger)width
                                    height:(NSInteger)height
{
    if(pixels == NULL || width <= 1 || height <= 1)
    {
        return @[];
    }
    _pixelsPerPoint = MAX(width / PGPhoneWidthPoints, 1.0);
    PGElementRect dialog = [self dialogRectIn:pixels width:width height:height];
    if(dialog.width > 0 && dialog.height > 0)
    {
        return [self segmentsIn:pixels width:width height:height clip:dialog typePrefix:@"dialog"];
    }
    PGElementRect full = {0, 0, width, height};
    return [self segmentsIn:pixels width:width height:height clip:full typePrefix:@"area"];
}

- (NSArray<PGElementNode *> *)nodesFromGray:(const uint8_t *)pixels
                                      width:(NSInteger)width
                                     height:(NSInteger)height
{
    NSMutableArray<PGElementNode *> *nodes = [NSMutableArray array];
    for(PGSegment *segment in [self segmentsFromGray:pixels width:width height:height])
    {
        if([self rectIsExcluded:segment.rect])
        {
            continue;
        }
        PGElementNode *node = [[PGElementNode alloc] init];
        node.type = segment.type;
        node.rect = segment.rect;
        node.visible = YES;
        // A container over half the screen is the page background or a full-width photo.
        BOOL backdrop = [segment.type hasSuffix:@"-container"] && segment.rect.width * segment.rect.height * 2 > width * height;
        node.clickable = !backdrop;
        node.children = @[];
        [nodes addObject:node];
    }
    [PGElementNode assignPaths:nodes parentPath:@""];
    return nodes;
}

- (PGElementRect)dialogRectIn:(const uint8_t *)pixels width:(NSInteger)width height:(NSInteger)height
{
    NSInteger marginX = width / 8;
    NSInteger marginY = height / 6;
    if(marginX < 2 || marginY < 2)
    {
        return (PGElementRect){0, 0, 0, 0};
    }
    uint64_t edgeSum = 0;
    NSInteger edgeCount = 0;
    for(NSInteger y = 0; y < height; y++)
    {
        for(NSInteger x = 0; x < width; x++)
        {
            BOOL edge = x < marginX || x >= width - marginX || y < marginY || y >= height - marginY;
            if(edge)
            {
                edgeSum += pixels[y * width + x];
                edgeCount += 1;
            }
        }
    }
    uint8_t edgeMean = edgeCount == 0 ? 0 : (uint8_t)(edgeSum / (uint64_t)edgeCount);
    NSInteger edgeInk = 0;
    for(NSInteger y = 0; y < height; y++)
    {
        for(NSInteger x = 0; x < width; x++)
        {
            BOOL edge = x < marginX || x >= width - marginX || y < marginY || y >= height - marginY;
            int delta = (int)pixels[y * width + x] - (int)edgeMean;
            if(edge && (delta > 24 || delta < -24))
            {
                edgeInk += 1;
            }
        }
    }
    // A dialog sits on a flat dimmed backdrop; title bars, tab bars and photos along the edges rule one out.
    if(edgeCount == 0 || edgeInk * 100 > edgeCount * PGDialogEdgeInkPercent)
    {
        return (PGElementRect){0, 0, 0, 0};
    }
    NSInteger minX = width, minY = height, maxX = 0, maxY = 0, hits = 0;
    for(NSInteger y = marginY; y < height - marginY; y++)
    {
        for(NSInteger x = marginX; x < width - marginX; x++)
        {
            int delta = (int)pixels[y * width + x] - (int)edgeMean;
            if(delta < 0) delta = -delta;
            if(delta > 24)
            {
                hits += 1;
                if(x < minX) minX = x;
                if(y < minY) minY = y;
                if(x > maxX) maxX = x;
                if(y > maxY) maxY = y;
            }
        }
    }
    NSInteger boxW = maxX - minX;
    NSInteger boxH = maxY - minY;
    if(hits < (width * height) / 40 || boxW < width / 5 || boxH < height / 8)
    {
        return (PGElementRect){0, 0, 0, 0};
    }
    // The search stops at the margins, so a box reaching them is content that runs to the screen edge.
    if(minX <= marginX + 1 || maxX >= width - marginX - 2 || minY <= marginY + 1 || maxY >= height - marginY - 2)
    {
        return (PGElementRect){0, 0, 0, 0};
    }
    return (PGElementRect){minX, minY, boxW, boxH};
}

- (NSArray<PGSegment *> *)segmentsIn:(const uint8_t *)pixels
                               width:(NSInteger)width
                              height:(NSInteger)height
                                clip:(PGElementRect)clip
                          typePrefix:(NSString *)typePrefix
{
    NSMutableArray<NSValue *> *rows = [NSMutableArray array];
    NSInteger rowStart = -1;
    for(NSInteger y = clip.top; y < clip.top + clip.height && y < height; y++)
    {
        BOOL ink = [self rowHasInk:pixels width:width y:y fromX:clip.left toX:clip.left + clip.width];
        if(ink && rowStart < 0)
        {
            rowStart = y;
        }
        if(!ink && rowStart >= 0)
        {
            [rows addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)rowStart, (NSUInteger)(y - rowStart))]];
            rowStart = -1;
        }
    }
    if(rowStart >= 0)
    {
        NSInteger end = MIN(clip.top + clip.height, height);
        [rows addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)rowStart, (NSUInteger)(end - rowStart))]];
    }
    NSMutableArray<PGSegment *> *segments = [NSMutableArray array];
    for(NSValue *rowValue in rows)
    {
        NSRange row = rowValue.rangeValue;
        [segments addObjectsFromArray:[self columnsIn:pixels width:width row:row clip:clip typePrefix:typePrefix]];
    }
    NSArray<PGSegment *> *merged = [self mergedOverlaps:segments];
    NSArray<PGSegment *> *images = [self imagesIn:pixels width:width height:height clip:clip typePrefix:typePrefix];
    return images.count == 0 ? merged : [self segments:merged collapsedInto:images pixels:pixels width:width];
}

// Edges inside a photo cut it into dozens of blocks that are all the same target, so each photo
// becomes one block. Flat UI keeps fine segments, and flat controls drawn over a photo stay.
- (NSArray<PGSegment *> *)segments:(NSArray<PGSegment *> *)segments
                      collapsedInto:(NSArray<PGSegment *> *)images
                             pixels:(const uint8_t *)pixels
                              width:(NSInteger)width
{
    NSMutableArray<PGSegment *> *kept = [NSMutableArray arrayWithArray:images];
    for(PGSegment *segment in segments)
    {
        PGSegment *cover = nil;
        for(PGSegment *image in images)
        {
            if([self rect:segment.rect insideRect:image.rect])
            {
                cover = image;
                break;
            }
        }
        if(cover == nil || [self dominantPercentIn:pixels width:width rect:segment.rect] >= 100 - PGImageDominantPercent / 2)
        {
            [kept addObject:segment];
        }
    }
    return kept;
}

- (BOOL)rect:(PGElementRect)inner insideRect:(PGElementRect)outer
{
    NSInteger left = MAX(inner.left, outer.left);
    NSInteger top = MAX(inner.top, outer.top);
    NSInteger right = MIN(inner.left + inner.width, outer.left + outer.width);
    NSInteger bottom = MIN(inner.top + inner.height, outer.top + outer.height);
    if(right <= left || bottom <= top)
    {
        return NO;
    }
    return (right - left) * (bottom - top) * 100 >= inner.width * inner.height * PGImageCoverPercent;
}

- (NSInteger)dominantPercentIn:(const uint8_t *)pixels width:(NSInteger)width rect:(PGElementRect)rect
{
    NSInteger stride = MAX(MIN(rect.width, rect.height) / 12, 1);
    NSInteger bins[16] = {0};
    NSInteger total = 0;
    for(NSInteger y = rect.top; y < rect.top + rect.height; y += stride)
    {
        for(NSInteger x = rect.left; x < rect.left + rect.width; x += stride)
        {
            bins[pixels[y * width + x] >> 4] += 1;
            total += 1;
        }
    }
    NSInteger top = 0;
    for(NSInteger i = 0; i < 16; i++)
    {
        top = MAX(top, bins[i]);
    }
    return total == 0 ? 100 : top * 100 / total;
}

- (NSArray<PGSegment *> *)imagesIn:(const uint8_t *)pixels
                             width:(NSInteger)width
                            height:(NSInteger)height
                              clip:(PGElementRect)clip
                        typePrefix:(NSString *)typePrefix
{
    NSInteger cell = MAX((NSInteger)lround(PGImageCellPoints * _pixelsPerPoint), 4);
    NSInteger columns = clip.width / cell;
    NSInteger rows = clip.height / cell;
    if(columns < 2 || rows < 2)
    {
        return @[];
    }
    NSInteger count = columns * rows;
    NSMutableData *medianData = [NSMutableData dataWithLength:(NSUInteger)count];
    uint8_t *medians = medianData.mutableBytes;
    NSMutableData *rangeData = [NSMutableData dataWithLength:(NSUInteger)count];
    uint8_t *ranges = rangeData.mutableBytes;
    NSInteger histogram[32] = {0};
    NSInteger step = MAX(cell / 6, 1);
    uint8_t samples[64];
    for(NSInteger row = 0; row < rows; row++)
    {
        for(NSInteger column = 0; column < columns; column++)
        {
            NSInteger left = clip.left + column * cell;
            NSInteger top = clip.top + row * cell;
            NSInteger taken = 0;
            for(NSInteger y = top; y < top + cell && taken < 64; y += step)
            {
                for(NSInteger x = left; x < left + cell && taken < 64; x += step)
                {
                    uint8_t value = pixels[y * width + x];
                    NSInteger slot = taken;
                    while(slot > 0 && samples[slot - 1] > value)
                    {
                        samples[slot] = samples[slot - 1];
                        slot -= 1;
                    }
                    samples[slot] = value;
                    taken += 1;
                }
            }
            uint8_t median = taken > 0 ? samples[taken / 2] : 0;
            medians[row * columns + column] = median;
            ranges[row * columns + column] = taken > 0 ? (uint8_t)(samples[taken - 1] - samples[0]) : 0;
            histogram[median >> 3] += 1;
        }
    }
    NSInteger backgroundBin = 0;
    for(NSInteger i = 1; i < 32; i++)
    {
        if(histogram[i] > histogram[backgroundBin])
        {
            backgroundBin = i;
        }
    }
    int background = (int)(backgroundBin * 8 + 4);
    NSMutableData *labelData = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(int32_t)];
    int32_t *labels = labelData.mutableBytes;
    for(NSInteger i = 0; i < count; i++)
    {
        int delta = (int)medians[i] - background;
        labels[i] = (delta > 24 || delta < -24) ? -1 : 0;
    }
    NSMutableData *queueData = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(int32_t)];
    int32_t *queue = queueData.mutableBytes;
    NSInteger minSide = (NSInteger)(PGImageMinSidePoints * _pixelsPerPoint);
    NSMutableArray<PGSegment *> *images = [NSMutableArray array];
    int32_t label = 0;
    for(NSInteger seed = 0; seed < count; seed++)
    {
        if(labels[seed] != -1)
        {
            continue;
        }
        label += 1;
        NSInteger head = 0;
        NSInteger tail = 0;
        queue[tail++] = (int32_t)seed;
        labels[seed] = label;
        NSInteger minColumn = columns, maxColumn = 0, minRow = rows, maxRow = 0;
        NSInteger shades[16] = {0};
        NSInteger textured = 0;
        while(head < tail)
        {
            NSInteger index = queue[head++];
            NSInteger row = index / columns;
            NSInteger column = index % columns;
            minColumn = MIN(minColumn, column);
            maxColumn = MAX(maxColumn, column);
            minRow = MIN(minRow, row);
            maxRow = MAX(maxRow, row);
            shades[medians[index] >> 4] += 1;
            textured += ranges[index] > PGImageCellRange ? 1 : 0;
            NSInteger neighbours[4] = {
                column > 0 ? index - 1 : -1,
                column + 1 < columns ? index + 1 : -1,
                row > 0 ? index - columns : -1,
                row + 1 < rows ? index + columns : -1
            };
            for(NSInteger n = 0; n < 4; n++)
            {
                if(neighbours[n] >= 0 && labels[neighbours[n]] == -1 && abs((int)medians[neighbours[n]] - (int)medians[index]) <= PGImageNeighbourJump)
                {
                    labels[neighbours[n]] = label;
                    queue[tail++] = (int32_t)neighbours[n];
                }
            }
        }
        NSInteger boxColumns = maxColumn - minColumn + 1;
        NSInteger boxRows = maxRow - minRow + 1;
        if(boxColumns * cell < minSide || boxRows * cell < minSide || tail * 100 < boxColumns * boxRows * PGImageFillPercent)
        {
            continue;
        }
        NSInteger dominant = 0;
        for(NSInteger i = 0; i < 16; i++)
        {
            dominant = MAX(dominant, shades[i]);
        }
        if(dominant * 100 >= tail * PGImageDominantPercent || textured * 100 < tail * PGImageTexturedPercent)
        {
            continue;
        }
        PGSegment *image = [[PGSegment alloc] init];
        image.rect = (PGElementRect){clip.left + minColumn * cell, clip.top + minRow * cell, boxColumns * cell, boxRows * cell};
        image.type = [typePrefix stringByAppendingString:@"-image"];
        [images addObject:image];
    }
    return images;
}

- (BOOL)rowHasInk:(const uint8_t *)pixels width:(NSInteger)width y:(NSInteger)y fromX:(NSInteger)fromX toX:(NSInteger)toX
{
    if(y < 0 || fromX >= toX)
    {
        return NO;
    }
    uint64_t sum = 0;
    NSInteger count = 0;
    NSInteger last = 0;
    NSInteger changes = 0;
    for(NSInteger x = MAX(fromX, 0); x < toX && x < width; x++)
    {
        uint8_t value = pixels[y * width + x];
        sum += value;
        if(count > 0 && (value > last + 18 || last > value + 18))
        {
            changes += 1;
        }
        last = value;
        count += 1;
    }
    return count > 0 && changes >= 2;
}

- (NSArray<PGSegment *> *)columnsIn:(const uint8_t *)pixels
                              width:(NSInteger)width
                                row:(NSRange)row
                               clip:(PGElementRect)clip
                         typePrefix:(NSString *)typePrefix
{
    NSMutableArray<PGSegment *> *columns = [NSMutableArray array];
    // Gaps between letters, words and photo texture stay inside one segment; a control is further apart.
    NSInteger bridge = MAX(width / PGColumnBridgeDivisor, 1);
    NSInteger colStart = -1;
    NSInteger lastInk = -1;
    NSInteger xEnd = MIN(clip.left + clip.width, width);
    for(NSInteger x = MAX(clip.left, 0); x <= xEnd; x++)
    {
        BOOL ink = x < xEnd && [self columnHasInk:pixels width:width x:x row:row];
        if(ink)
        {
            if(colStart < 0)
            {
                colStart = x;
            }
            lastInk = x;
            continue;
        }
        if(colStart >= 0 && (x - lastInk > bridge || x == xEnd))
        {
            NSInteger right = lastInk + 1;
            if(right - colStart >= PGSegmentMinPixels && (NSInteger)row.length >= PGSegmentMinPixels)
            {
                PGSegment *segment = [[PGSegment alloc] init];
                segment.rect = (PGElementRect){colStart, (NSInteger)row.location, right - colStart, (NSInteger)row.length};
                segment.type = [self typeForRect:segment.rect prefix:typePrefix];
                [columns addObject:segment];
            }
            colStart = -1;
        }
    }
    return columns;
}

- (BOOL)columnHasInk:(const uint8_t *)pixels width:(NSInteger)width x:(NSInteger)x row:(NSRange)row
{
    NSInteger changes = 0;
    NSInteger last = 0;
    for(NSUInteger i = 0; i < row.length; i++)
    {
        NSInteger y = (NSInteger)row.location + (NSInteger)i;
        uint8_t value = pixels[y * width + x];
        if(i > 0 && (value > last + 18 || last > value + 18))
        {
            changes += 1;
        }
        last = value;
    }
    return changes >= 1;
}

- (NSString *)typeForRect:(PGElementRect)rect prefix:(NSString *)prefix
{
    double unit = _pixelsPerPoint > 0 ? _pixelsPerPoint : 1;
    double width = rect.width / unit;
    double height = rect.height / unit;
    if(height > 0 && height < 40 && width / height >= 4)
    {
        return [prefix stringByAppendingString:@"-text"];
    }
    if(width < 64 && height < 64)
    {
        return [prefix stringByAppendingString:@"-icon"];
    }
    if(width > 14 && height >= 10 && height < 64)
    {
        return [prefix stringByAppendingString:@"-button"];
    }
    return [prefix stringByAppendingString:@"-container"];
}

- (NSArray<PGSegment *> *)mergedOverlaps:(NSArray<PGSegment *> *)segments
{
    NSMutableArray<PGSegment *> *merged = [NSMutableArray array];
    for(PGSegment *segment in segments)
    {
        PGSegment *hit = nil;
        for(PGSegment *existing in merged)
        {
            if([self rect:existing.rect overlaps:segment.rect] || [self segment:existing isSimilarTo:segment])
            {
                hit = existing;
                break;
            }
        }
        if(hit == nil)
        {
            [merged addObject:segment];
        }
        else
        {
            NSInteger left = MIN(hit.rect.left, segment.rect.left);
            NSInteger top = MIN(hit.rect.top, segment.rect.top);
            NSInteger right = MAX(hit.rect.left + hit.rect.width, segment.rect.left + segment.rect.width);
            NSInteger bottom = MAX(hit.rect.top + hit.rect.height, segment.rect.top + segment.rect.height);
            hit.rect = (PGElementRect){left, top, right - left, bottom - top};
            NSString *prefix = [hit.type componentsSeparatedByString:@"-"].firstObject;
            if(prefix.length == 0)
            {
                prefix = @"area";
            }
            hit.type = [self typeForRect:hit.rect prefix:prefix];
        }
    }
    return merged;
}

- (BOOL)rect:(PGElementRect)a overlaps:(PGElementRect)b
{
    NSInteger aRight = a.left + a.width;
    NSInteger bRight = b.left + b.width;
    NSInteger aBottom = a.top + a.height;
    NSInteger bBottom = b.top + b.height;
    return a.left < bRight && b.left < aRight && a.top < bBottom && b.top < aBottom;
}

- (BOOL)segment:(PGSegment *)existing isSimilarTo:(PGSegment *)segment
{
    NSString *leftPrefix = [existing.type componentsSeparatedByString:@"-"].firstObject ?: @"";
    NSString *rightPrefix = [segment.type componentsSeparatedByString:@"-"].firstObject ?: @"";
    if(![leftPrefix isEqualToString:rightPrefix])
    {
        return NO;
    }
    NSInteger dx = (existing.rect.left + existing.rect.width / 2) - (segment.rect.left + segment.rect.width / 2);
    NSInteger dy = (existing.rect.top + existing.rect.height / 2) - (segment.rect.top + segment.rect.height / 2);
    if(dx < 0) dx = -dx;
    if(dy < 0) dy = -dy;
    return dx <= 16 && dy <= 16;
}

- (BOOL)rectIsExcluded:(PGElementRect)rect
{
    NSInteger centerX = rect.left + rect.width / 2;
    NSInteger centerY = rect.top + rect.height / 2;
    for(id item in self.excludeRects)
    {
        NSInteger left = 0, top = 0, width = 0, height = 0;
        if([item isKindOfClass:[NSDictionary class]])
        {
            NSDictionary *box = item;
            left = [box[@"left"] integerValue];
            top = [box[@"top"] integerValue];
            width = [box[@"width"] integerValue];
            height = [box[@"height"] integerValue];
        }
        else if([item isKindOfClass:[NSArray class]] && [(NSArray *)item count] >= 4)
        {
            NSArray *box = item;
            left = [box[0] integerValue];
            top = [box[1] integerValue];
            width = [box[2] integerValue];
            height = [box[3] integerValue];
        }
        else
        {
            continue;
        }
        if(width > 0 && height > 0 && centerX >= left && centerY >= top && centerX <= left + width && centerY <= top + height)
        {
            return YES;
        }
    }
    return NO;
}

@end
