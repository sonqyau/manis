package main

import "C"
import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
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
	ErrCodeInvalidPath     = -7
)

var (
	gate sync.RWMutex
	instances = make(map[uintptr]*instanceCtx)
	nextHandle uintptr = 1
	lastError string = ""
)

type instanceCtx struct {
	handle     uintptr
	created    bool
	started    bool
	configPath string
	ctx        context.Context
	cancel     context.CancelFunc
}

func nextInstanceHandle() uintptr {
	handle := nextHandle
	nextHandle++
	return handle
}

func setLastError(err string) {
	gate.Lock()
	lastError = err
	gate.Unlock()
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

func validateConfigPath(configPath string) error {
	if configPath == "" {
		return errors.New("config path is empty")
	}
	
	if _, err := os.Stat(configPath); err != nil {
		return fmt.Errorf("config path not accessible: %v", err)
	}
	
	ext := filepath.Ext(configPath)
	if ext != ".yaml" && ext != ".yml" {
		return errors.New("config file must be YAML format")
	}
	
	return nil
}

//export mihomo_create
func mihomo_create(configPath *C.char) C.longlong {
	if configPath == nil {
		setLastError("config path is null")
		return C.longlong(ErrCodeInvalidConfig)
	}
	
	config := C.GoString(configPath)
	if err := validateConfigPath(config); err != nil {
		setLastError(err.Error())
		return C.longlong(ErrCodeInvalidConfig)
	}
	
	gate.Lock()
	defer gate.Unlock()
	
	for _, instance := range instances {
		if instance.configPath == config {
			setLastError("instance with this config already exists")
			return C.longlong(ErrCodeAlreadyCreated)
		}
	}
	
	ctx, cancel := context.WithCancel(context.Background())
	
	instance := &instanceCtx{
		handle:     nextInstanceHandle(),
		created:    true,
		started:    false,
		configPath: config,
		ctx:        ctx,
		cancel:     cancel,
	}
	
	instances[instance.handle] = instance
	setLastError("")
	return C.longlong(instance.handle)
}

//export mihomo_start
func mihomo_start(handle C.longlong) C.int {
	instance, err := getInstance(handle)
	if err != nil {
		setLastError(err.Error())
		return ErrCodeInvalidHandle
	}
	
	gate.Lock()
	defer gate.Unlock()
	
	if instance.started {
		setLastError("instance already started")
		return ErrCodeAlreadyStarted
	}
	
	instance.started = true
	setLastError("")
	return ErrCodeSuccess
}

//export mihomo_stop
func mihomo_stop(handle C.longlong) C.int {
	instance, err := getInstance(handle)
	if err != nil {
		setLastError(err.Error())
		return ErrCodeInvalidHandle
	}
	
	gate.Lock()
	defer gate.Unlock()
	
	if !instance.started {
		setLastError("instance not started")
		return ErrCodeNotStarted
	}
	
	instance.started = false
	if instance.cancel != nil {
		instance.cancel()
	}
	
	setLastError("")
	return ErrCodeSuccess
}

//export mihomo_destroy
func mihomo_destroy(handle C.longlong) C.int {
	h := uintptr(handle)
	
	gate.Lock()
	defer gate.Unlock()
	
	instance, exists := instances[h]
	if !exists {
		setLastError("invalid handle")
		return ErrCodeInvalidHandle
	}
	
	if instance.started {
		instance.started = false
		if instance.cancel != nil {
			instance.cancel()
		}
	}
	
	delete(instances, h)
	setLastError("")
	return ErrCodeSuccess
}

//export mihomo_is_running
func mihomo_is_running(handle C.longlong) C.int {
	instance, err := getInstance(handle)
	if err != nil {
		setLastError(err.Error())
		return 0
	}
	
	gate.RLock()
	running := instance.started
	gate.RUnlock()
	
	if running {
		return 1
	}
	return 0
}

//export mihomo_get_version
func mihomo_get_version() *C.char {
	version := "1.18.0-alpha"
	return C.CString(version)
}

//export mihomo_free_string
func mihomo_free_string(ptr *C.char) {
	if ptr != nil {
		C.free(unsafe.Pointer(ptr))
	}
}

//export mihomo_get_last_error
func mihomo_get_last_error() *C.char {
	gate.RLock()
	err := lastError
	gate.RUnlock()
	
	if err == "" {
		err = "No error"
	}
	return C.CString(err)
}

//export mihomo_validate_config
func mihomo_validate_config(configPath *C.char) C.int {
	if configPath == nil {
		setLastError("config path is null")
		return ErrCodeInvalidConfig
	}
	
	config := C.GoString(configPath)
	if err := validateConfigPath(config); err != nil {
		setLastError(err.Error())
		return ErrCodeInvalidPath
	}

	if _, err := os.ReadFile(config); err != nil {
		setLastError(fmt.Sprintf("cannot read config file: %v", err))
		return ErrCodeInvalidConfig
	}
	
	setLastError("")
	return ErrCodeSuccess
}

func main() {}
