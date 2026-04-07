#import "SZOperationSessionDefaults.h"

#import "../Dialogs/SZDialogPresenter.h"

static SZDialogStyle SZDialogStyleForPromptStyle(SZOperationPromptStyle style) {
    switch (style) {
        case SZOperationPromptStyleWarning:
            return SZDialogStyleWarning;
        case SZOperationPromptStyleCritical:
            return SZDialogStyleCritical;
        case SZOperationPromptStyleInformational:
        default:
            return SZDialogStyleInformational;
    }
}

SZOperationSession *SZMakeDefaultOperationSession(id<SZProgressDelegate> progressDelegate) {
    SZOperationSession *session = [SZOperationSession new];
    session.progressDelegate = progressDelegate;
    session.passwordRequestHandler = ^BOOL(NSString *title,
                                           NSString *message,
                                           NSString *initialValue,
                                           NSString * _Nullable * _Nullable password) {
        return [SZDialogPresenter promptForPasswordWithTitle:title
                                                     message:message
                                                initialValue:initialValue
                                                     password:password];
    };
    session.choiceRequestHandler = ^NSInteger(SZOperationPromptStyle style,
                                              NSString *title,
                                              NSString *message,
                                              NSArray<NSString *> *buttonTitles) {
        return [SZDialogPresenter runMessageWithStyle:SZDialogStyleForPromptStyle(style)
                                                title:title
                                              message:message
                                         buttonTitles:buttonTitles];
    };
    return session;
}
