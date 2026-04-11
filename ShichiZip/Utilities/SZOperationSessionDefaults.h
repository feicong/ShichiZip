#import <Foundation/Foundation.h>

#import "../Bridge/SZArchive.h"
#import "../Bridge/SZOperationSession.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT SZOperationSession* SZMakeDefaultOperationSession(id<SZProgressDelegate> _Nullable progressDelegate);

NS_ASSUME_NONNULL_END
