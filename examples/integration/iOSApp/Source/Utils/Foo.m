#import "Foo.h"
#import "external/FXPageControl/FXPageControl/FXPageControl.h"

@implementation Foo

- (NSString *)greeting {
    return @"Hello, world?";
}

- (NSInteger)answer {
    return [Answers new].answer;
}

@end
