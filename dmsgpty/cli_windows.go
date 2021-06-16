//+build windows

package dmsgpty

import (
	"context"
	"fmt"
	"os"
	"time"
)

const (
	windowsPollResizeDuration = 1 * time.Second
)

// ptyResizeLoop informs the remote of changes to the local CLI terminal window size.
func ptyResizeLoop(ctx context.Context, ptyC *PtyClient) error {
	// has to be polled manually on windows, there's no SIGWINCH
	timer := time.NewTicker(windowsPollResizeDuration)
	for {
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil
		case <-timer.C:
			winSize, err := getPtySize(os.Stdout)
			if err != nil {
				return fmt.Errorf("failed to obtain window size: %v", err)
			}
			if err := ptyC.SetPtySize(winSize); err != nil {
				return fmt.Errorf("failed to set remote window size: %v", err)
			}
		}
	}
}
