//
// Created by r53wang on 3/23/23.
//

#ifndef semalloc_DEBUG_HH
#define semalloc_DEBUG_HH
#include <stdio.h>

#define RED     "\x1b[31m"
#define YELLOW  "\x1b[33m"
#define GREEN   "\x1b[32m"
#define END     "\x1b[0m"


#ifdef DEBUG // debug only
#define WARN
#define INFO
#else
#endif // end debug

#ifdef DEBUG // debug only
#define INFO
#define Debug(fmt, ...) \
  do { \
    fprintf(stderr, YELLOW "[ln %d] in %s " fmt END, \
             __LINE__, __func__,  __VA_ARGS__); \
  } while(0)

#define Canary(fmt, ...) \
  do { \
    fprintf(stderr, GREEN "%s " fmt END, __func__, __VA_ARGS__); \
  } while(0) /* canary related print */
#else
#define Debug(...)
#define Canary( ...)
#endif // end debug

#ifdef INFO // debug only
#define INFO2
#define Info(fmt, ...) \
  do { \
    fprintf(stderr, YELLOW "[ln %d] in %s " fmt END, \
             __LINE__, __func__,  __VA_ARGS__); \
  } while(0)
#else
#define Info(...)
#endif // end info

#ifdef INFO2 // debug only
#define Info2(fmt, ...) \
  do { \
    fprintf(stderr, YELLOW "[ln %d] in %s " fmt END, \
             __LINE__, __func__,  __VA_ARGS__); \
  } while(0)
#else
#define Info2(...)
#endif // end Info2

#ifdef WARN // debug only
#define Warn(fmt, ...) \
  do { \
    fprintf(stderr, YELLOW "[ln %d] in %s " fmt END, \
             __LINE__, __func__,  __VA_ARGS__); \
  } while(0)
#else
#define Warn(...)
#endif // end warn


#define Error(fmt, ...) \
  do{ \
    fprintf(stderr, RED "ERROR: %s #%d " fmt END, \
           __func__, __LINE__,  __VA_ARGS__); \
  } while(0)

#define Print(fmt, ...) \
  do { \
    fprintf(stderr, "[%d:] %s ", \
            __LINE__ , __func__, __VA_ARGS__); \
  } while(0)

#ifdef ENABLE_ASSERTS
#include <assert.h>
#define Assert(truth, message)                                                                      \
	do {                                                                                                     \
		if (!(truth)) {                                                                                      \
            assert((truth) && message);                                                                      \
		}                                                                                                    \
	} while (0)
#else
#define Assert(truth, message) do {} while(0)
#endif


#endif //semalloc_DEBUG_HH
