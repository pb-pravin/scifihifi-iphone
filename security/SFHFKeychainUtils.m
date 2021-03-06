//
//  SFHFKeychainUtils.m
//
//  Created by Buzz Andersen on 10/20/08.
//  Based partly on code by Jonathan Wight, Jon Crosby, and Mike Malone.
//  Copyright 2008 Sci-Fi Hi-Fi. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#import "SFHFKeychainUtils.h"
#import <Security/Security.h>

#if TARGET_OS_MAC == 1
//
// Security.framework on 10.6 has two issues compared to the iPhone version
// 1. Security.h doesn't include SecItem.h
// 2. kSecClassGenericPassword is not declared in SecItem.h
//

#import <Security/SecItem.h>

//extern const CFTypeRef kSecClassGenericPassword;
extern CFTypeRef kSecClassGenericPassword __OSX_AVAILABLE_STARTING(__MAC_NA, __IPHONE_2_0);

#endif // TARGET_OS_MAC

static NSString *SFHFKeychainUtilsErrorDomain = @"SFHFKeychainUtilsErrorDomain";


@implementation SFHFKeychainUtils


+ (NSString *)getPasswordForUsername:(NSString *)username
                      andServiceName:(NSString *)serviceName
                            uniqueID:(NSString *)uniqueIDOrNil
                         accessGroup:(NSString *)accessGroupNameOrNil
                               error:(NSError **)error
{
    if (([username length] == 0) || ([serviceName length] == 0))
    {
        if (error != nil)
        {
            *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
        }
        return nil;
    }
    
    if (error != nil)
    {
        *error = nil;
    }
    
    // Set up a query dictionary with the base query attributes: item type (generic), username, and service
    NSMutableDictionary *query = [[[NSMutableDictionary alloc] init] autorelease];
    [query setObject:kSecClassGenericPassword forKey:kSecClass];
    [query setObject:username forKey:kSecAttrAccount];
    [query setObject:serviceName forKey:kSecAttrService];

    // First do a query for attributes, in case we already have a Keychain item with no password data set.
    // One likely way such an incorrect item could have come about is due to the previous (incorrect)
    // version of this code (which set the password as a generic attribute instead of password data).
    
    NSDictionary *attributeResult = nil;
    NSMutableDictionary *attributeQuery = [[query mutableCopy] autorelease];
    [attributeQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];

    // Check if there's a shared keychain access group name provided and set it appropriately.
    // NOTE: this won't work for *pre* iOS 3.0 simulators (devices work fine).
    if (accessGroupNameOrNil)
    {
        // Don't add empty string as access group specifier
        if ([accessGroupNameOrNil length] == 0)
        {
            if (error != nil)
            {
                *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
            }
            return nil;
        }
        else
        {
            NSLog(@"Adding access group.");
            [attributeQuery setObject:(id)accessGroupNameOrNil forKey:(id)kSecAttrAccessGroup];
        }
    }
    if (uniqueIDOrNil)
    {
        // Don't add empty string as unique identifier attribute
        if ([uniqueIDOrNil length] == 0)
        {
            if (error != nil)
            {
                *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
            }
            return nil;
        }
        else
        {
            NSLog(@"Adding unique identifier.");
            [attributeQuery setObject:(id)uniqueIDOrNil forKey:(id)kSecAttrGeneric];
        }
    }

    OSStatus status = SecItemCopyMatching((CFDictionaryRef)attributeQuery, (CFTypeRef *)&attributeResult);
    if (status != noErr)
    {
        // No existing item found--simply return nil for the password
        if (status != errSecItemNotFound)
        {
            //Only return an error if a real exception happened--not simply for "not found."
            if (error != nil)
            {
                *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:status userInfo:nil];
            }
        }
        [attributeResult release];
        return nil;
    }
    
    [attributeResult release];
    
    // We have an existing item, now query for the password data associated with it.
    
    NSData *resultData = nil;
    NSMutableDictionary *passwordQuery = [[query mutableCopy] autorelease];
    [passwordQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];

    // Remember to uniqueIDOrNil and accessGroupNameOrNil to passwordQuery (they're not present in query object)
    if (accessGroupNameOrNil)
    {
        // Don't add empty string as access group specifier
        if ([accessGroupNameOrNil length] == 0)
        {
            if (error != nil)
            {
                *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
            }
            return nil;
        }
        else
        {
            NSLog(@"Adding access group.");
            [passwordQuery setObject:(id)accessGroupNameOrNil forKey:(id)kSecAttrAccessGroup];
        }
    }
    if (uniqueIDOrNil)
    {
        // Don't add empty string as unique identifier attribute
        if ([uniqueIDOrNil length] == 0)
        {
            if (error != nil)
            {
                *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
            }
            return nil;
        }
        else
        {
            NSLog(@"Adding unique identifier.");
            [passwordQuery setObject:(id)uniqueIDOrNil forKey:(id)kSecAttrGeneric];
        }
    }
    
    status = SecItemCopyMatching((CFDictionaryRef)passwordQuery, (CFTypeRef *)&resultData);

    [resultData autorelease];
    
    if (status != noErr)
    {
        if (status == errSecItemNotFound)
        {
            // We found attributes for the item previously, but no password now, so return a special error.
            // Users of this API will probably want to detect this error and prompt the user to
            // re-enter their credentials.  When you attempt to store the re-entered credentials
            // using storeUsername:andPassword:forServiceName:updateExisting:error
            // the old, incorrect entry will be deleted and a new one with a properly encrypted
            // password will be added.
            if (error != nil)
            {
                *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-1999 userInfo:nil];
            }
        }
        else
        {
            // Something else went wrong. Simply return the normal Keychain API error code.
            if (error != nil)
            {
                *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:status userInfo:nil];
            }
        }
        
        return nil;
    }
  
    NSString *password = nil;
  
    if (resultData)
    {
        password = [[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding];
    }
    else
    {
        // There is an existing item, but we weren't able to get password data for it for some reason,
        // Possibly as a result of an item being incorrectly entered by the previous code.
        // Set the -1999 error so the code above us can prompt the user again.
        if (error != nil)
        {
            *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-1999 userInfo:nil];
        }
        return nil;
    }
    
    return [password autorelease];
}


+ (BOOL)storeUsername:(NSString *)username
          andPassword:(NSString *)password
       forServiceName:(NSString *)serviceName
             uniqueID:(NSString *)uniqueIDOrNil
          accessGroup:(NSString *)accessGroupNameOrNil
       updateExisting:(BOOL)updateExisting
                error:(NSError **)error
{
    NSError *getError = nil;
    NSString *existingPassword;

    if (([username length] == 0) || ([password length] == 0) || ([serviceName length] == 0))
    {
        if (error != nil)
        {
            *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
        }
        return NO;
    }
    
    // See if we already have a password entered for these credentials.
    existingPassword = [SFHFKeychainUtils getPasswordForUsername:username
                                                  andServiceName:serviceName
                                                        uniqueID:uniqueIDOrNil
                                                     accessGroup:accessGroupNameOrNil
                                                           error:&getError];
    if ([getError code] == -1999)
    {
        // There is an existing entry without a password properly stored (possibly as a result of the previous incorrect version of this code.
        // Delete the existing item before moving on entering a correct one.
        getError = nil;
        [self deleteItemForUsername:username
                     andServiceName:serviceName
                           uniqueID:uniqueIDOrNil
                        accessGroup:accessGroupNameOrNil
                              error:&getError];
        if ([getError code] != noErr)
        {
            if (error != nil)
            {
                *error = getError;
            }
            return NO;
        }
    }
    else if ([getError code] != noErr)
    {
        if (error != nil)
        {
            *error = getError;
        }
        return NO;
    }

    if (error != nil)
    {
        *error = nil;
    }

    OSStatus status = noErr;
  
    if (existingPassword)
    {
        // We have an existing, properly entered item with a password.
        // Update the existing item.
        
        if (![existingPassword isEqualToString:password] && updateExisting)
        {
            //Only update if we're allowed to update existing.  If not, simply do nothing.
            NSMutableDictionary *mutableQuery = [[[NSMutableDictionary alloc] init] autorelease];
            [mutableQuery setObject:kSecClassGenericPassword forKey:kSecClass];
            [mutableQuery setObject:serviceName forKey:kSecAttrService];
            [mutableQuery setObject:serviceName forKey:kSecAttrLabel];
            [mutableQuery setObject:username forKey:kSecAttrAccount];

            // Check if there's a shared keychain access group name provided and set it appropriately.
            // NOTE: this won't work for *pre* iOS 3.0 simulators (devices work fine).
            if (accessGroupNameOrNil)
            {
                // Don't add empty string as access group specifier
                if ([accessGroupNameOrNil length] == 0)
                {
                    if (error != nil)
                    {
                        *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
                    }
                    return NO;
                }
                else
                {
                    NSLog(@"Adding access group.");
                
                    [mutableQuery setObject:(id)accessGroupNameOrNil forKey:(id)kSecAttrAccessGroup];
                }
            }
            if (uniqueIDOrNil)
            {
                // Don't add empty string as unique identifier attribute
                if ([uniqueIDOrNil length] == 0)
                {
                    if (error != nil)
                    {
                        *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
                    }
                    return NO;
                }
                else
                {
                    NSLog(@"Adding unique identifier.");
                    [mutableQuery setObject:(id)uniqueIDOrNil forKey:(id)kSecAttrGeneric];
                }
            }
            
            status = SecItemUpdate((CFDictionaryRef)mutableQuery, (CFDictionaryRef)[NSDictionary dictionaryWithObject:[password dataUsingEncoding:NSUTF8StringEncoding] forKey:(NSString *)kSecValueData]);
        }
    }
    else 
    {
        // No existing entry (or an existing, improperly entered, and therefore now
        // deleted, entry).  Create a new entry.

        NSMutableDictionary *mutableQuery = [[[NSMutableDictionary alloc] init] autorelease];
        [mutableQuery setObject:kSecClassGenericPassword forKey:kSecClass];
        [mutableQuery setObject:serviceName forKey:kSecAttrService];
        [mutableQuery setObject:serviceName forKey:kSecAttrLabel];
        [mutableQuery setObject:username forKey:kSecAttrAccount];
        [mutableQuery setObject:[password dataUsingEncoding:NSUTF8StringEncoding] forKey:kSecValueData];

        // Check if there's a shared keychain access group name provided and set it appropriately.
        // NOTE: this won't work for *pre* iOS 3.0 simulators (devices work fine).
        if (accessGroupNameOrNil)
        {
            // Don't add empty string as access group specifier
            if ([accessGroupNameOrNil length] == 0)
            {
                if (error != nil)
                {
                    *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
                }
                return NO;
            }
            else
            {
                NSLog(@"getPasswordForUsername: adding access group.");
                [mutableQuery setObject:accessGroupNameOrNil forKey:(id)kSecAttrAccessGroup];
            }
        }
        if (uniqueIDOrNil)
        {
            // Don't add empty string as unique identifier attribute
            if ([uniqueIDOrNil length] == 0)
            {
                if (error != nil)
                {
                    *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
                }
                return NO;
            }
            else
            {
                NSLog(@"Adding unique identifier.");
                [mutableQuery setObject:(id)uniqueIDOrNil forKey:(id)kSecAttrGeneric];
            }
        }

        status = SecItemAdd((CFDictionaryRef)mutableQuery, NULL);
    }
    
    if (status != noErr)
    {
        // Something went wrong with adding the new item. Return the Keychain error code.
        if (error != nil)
        {
            *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    return YES;
}


+ (BOOL)deleteItemForUsername:(NSString *)username
               andServiceName:(NSString *)serviceName
                     uniqueID:(NSString *)uniqueIDOrNil
                  accessGroup:(NSString *)accessGroupNameOrNil
                        error:(NSError **)error
{
    if (([username length] == 0) || ([serviceName length] == 0))
    {
        if (error != nil)
        {
            *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
        }
        return NO;
    }
    
    if (error != nil)
    {
        *error = nil;
    }
    
    NSMutableDictionary *mutableQuery = [[[NSMutableDictionary alloc] init] autorelease];
    [mutableQuery setObject:kSecClassGenericPassword forKey:kSecClass];
    [mutableQuery setObject:username forKey:kSecAttrAccount];
    [mutableQuery setObject:serviceName forKey:kSecAttrService];
    [mutableQuery setObject:(id)kCFBooleanTrue forKey:kSecReturnAttributes];
    
    // Check if there's a shared keychain access group name provided and set it appropriately.
    // NOTE: this won't work for *pre* iOS 3.0 simulators (devices work fine).
    if (accessGroupNameOrNil)
    {
        // Don't add empty string as access group specifier
        if ([accessGroupNameOrNil length] == 0)
        {
            if (error != nil)
            {
                *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
            }
            return NO;
        }
        else
        {
            NSLog(@"getPasswordForUsername: adding access group.");
            [mutableQuery setObject:accessGroupNameOrNil forKey:(id)kSecAttrAccessGroup];
        }
    }
    if (uniqueIDOrNil)
    {
        // Don't add empty string as unique identifier attribute
        if ([uniqueIDOrNil length] == 0)
        {
            if (error != nil)
            {
                *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:-2000 userInfo:nil];
            }
            return NO;
        }
        else
        {
            NSLog(@"Adding unique identifier.");
            [mutableQuery setObject:(id)uniqueIDOrNil forKey:(id)kSecAttrGeneric];
        }
    }
    
    OSStatus status = SecItemDelete((CFDictionaryRef)mutableQuery);
    
    if (status != noErr)
    {
        if (error != nil)
        {
            *error = [NSError errorWithDomain:SFHFKeychainUtilsErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    return YES;
}

@end