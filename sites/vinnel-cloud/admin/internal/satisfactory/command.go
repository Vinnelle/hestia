package satisfactory

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

const (
	satisfactoryPrivilege  = "Administrator"
	satisfactoryMaxCommand = 512
)

func (s *Service) login() (string, error) {
	data := map[string]string{"MinimumPrivilegeLevel": satisfactoryPrivilege}
	fn := "PasswordlessLogin"
	if s.AdminPassword != "" {
		fn = "PasswordLogin"
		data["Password"] = s.AdminPassword
	}
	raw, err := apiCall(commandClient, s.Host, "", fn, data)
	if err != nil {
		return "", err
	}
	var out struct {
		AuthenticationToken string `json:"authenticationToken"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", err
	}
	if out.AuthenticationToken == "" {
		return "", fmt.Errorf("%s returned no authentication token", fn)
	}
	return out.AuthenticationToken, nil
}

func (s *Service) Command(cmd string) (string, error) {
	cmd = strings.TrimSpace(cmd)
	if cmd == "" {
		return "", errors.New("empty command")
	}
	if len(cmd) > satisfactoryMaxCommand {
		return "", fmt.Errorf("command longer than %d bytes", satisfactoryMaxCommand)
	}
	if strings.ContainsAny(cmd, "\n\r\x00") {
		return "", errors.New("command contains a control character")
	}
	if s.Host == "" {
		return "", errors.New("SATISFACTORY_HOST not configured")
	}
	token, err := s.login()
	if err != nil {
		return "", err
	}
	raw, err := apiCall(commandClient, s.Host, token, "RunCommand", map[string]string{"Command": cmd})
	if err != nil {
		return "", err
	}
	var out struct {
		CommandResult string `json:"commandResult"`
		ReturnValue   bool   `json:"returnValue"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", err
	}
	if !out.ReturnValue && out.CommandResult == "" {
		return "", errors.New("command failed")
	}
	return out.CommandResult, nil
}
