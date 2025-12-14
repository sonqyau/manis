package main

import "C"
import (
	"errors"
	"sync"
	"unsafe"
)

/*
#include <stdlib.h>
*/
import "C"

const (
	ErrCodeSuccess         = 0
	ErrCodeInvalidHandle   = -1
	ErrCodeAlreadyCreated  = -2
	ErrCodeAlreadyStarted  = -3
	ErrCodeNotStarted      = -4
	ErrCodeInvalidConfig   = -5
	ErrCodeInternalError   = -6
)

var (
	gate sync.RWMutex
	instances = make(map[uintptr]*instanceCtx)
	nextHandle uintptr = 1
)

type instanceCtx struct {
	handle     uintptr
	created    bool
	started    bool
	configPath string
}

func nextInstanceHandle() uintptr {
	handle := nextHandle
	nextHandle++
	return handle
}

func getInstance(handle C.longlong) (*instanceCtx, error) {
	h := uintptr(handle)
	
	gate.RLock()
	defer gate.RUnlock()
	
	instance, exists := instances[h]
	if !exists || !instance.created {
		return nil, errors.New("invalid handle")
	}
	
	return instance, nil
}

//export mihomo_create
func mihomo_create(configPath *C.char) C.longlong {
	if configPath == nil {
		return C.longlong(ErrCodeInvalidConfig)
	}
	
	config := C.GoString(configPath)
	if config == "" {
		return C.longlong(ErrCodeInvalidConfig)
	}
	
	gate.Lock()
	defer gate.Unlock()
	
	for _, instance := range instances {
		if instance.configPath == config {
			return C.longlong(ErrCodeAlreadyCreated)
		}
	}
	
	instance := &instanceCtx{
		handle:     nextInstanceHandle(),
		created:    true,
		started:    false,
		configPath: config,
	}
	
	instances[instance.handle] = instance
	return C.longlong(instance.handle)
}

//export mihomo_destroy
func mihomo_destroy(handle C.longlong) C.int {
	h := uintptr(handle)
	
	gate.Lock()
	defer gate.Unlock()
	
	instance, exists := instances[h]
	if !exists {
		return ErrCodeInvalidHandle
	}
	
	if instance.started {
		instance.started = false
	}
	
	delete(instances, h)
	return ErrCodeSuccess
}

//export mihomo_free_string
func mihomo_free_string(ptr *C.char) {
	if ptr != nil {
		C.free(unsafe.Pointer(ptr))
	}
}

//export mihomo_get_last_error
func mihomo_get_last_error() *C.char {
	errorMsg := "No error"
	return C.CString(errorMsg)
}

func main() {}
