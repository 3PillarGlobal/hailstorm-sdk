import React from 'react';
import { shallow, mount } from 'enzyme';
import { ProjectConfiguration } from './ProjectConfiguration';
import { render, fireEvent, wait } from '@testing-library/react';
import { ProjectService } from "../services/ProjectService";
import { AppState, Action } from '../store';
import { WizardTabTypes } from "../NewProjectWizard/domain";
import { AppStateContext } from '../appStateContext';
import { CreateProjectAction, ConfirmProjectSetupCancelAction, UpdateProjectTitleAction } from '../NewProjectWizard/actions';
import { AppNotificationContextProps } from '../app-notifications';
import { AppNotificationProviderWithProps } from '../AppNotificationProvider/AppNotificationProvider';

jest.mock('../DangerProjectSettings', () => ({
  __esModule: true,
  DangerProjectSettings: () => (
    <div id="DangerProjectSettings"></div>
  )
}));

describe('<ProjectConfiguration />', () => {

  function createNotifiers(notifiers: {
    [K in keyof(AppNotificationContextProps)]?: AppNotificationContextProps[K]
  }): AppNotificationContextProps {

    return {
      notifySuccess: jest.fn(),
      notifyError: jest.fn(),
      notifyInfo: jest.fn(),
      notifyWarning: jest.fn(),
      ...notifiers
    }
  }

  it('should render without crashing', () => {
    shallow(<ProjectConfiguration />);
  });

  it('should disable primary button initially', async () => {
    const {findByText} = render(
      <ProjectConfiguration />
    );

    const button = await findByText('Save & Next');
    expect(button.hasAttribute('disabled')).toBeTruthy();
  });

  it('should enable primary button on text input', async () => {
    const {findByPlaceholderText, findByText} = render(
      <ProjectConfiguration />
    );

    const textBox = await findByPlaceholderText('Project Title...');
    fireEvent.change(textBox, {target: {value: 'Some Title'}});
    const button = await findByText('Save & Next');
    expect(button.hasAttribute('disabled')).toBeFalsy();
  });

  it('should create new project on submit', async () => {
    jest.spyOn(ProjectService.prototype, 'create').mockResolvedValueOnce({
      id: 1, code: 'a', title: 'A', autoStop: false, running: true
    });

    const appState: AppState = {
      runningProjects: [],
      activeProject: undefined,
      wizardState: {
        activeTab: WizardTabTypes.Project,
        done: {}
      }
    }

    const dispatch = jest.fn();
    const notifySuccess = jest.fn();
    const {findByPlaceholderText, findByText} = render(
      <AppStateContext.Provider value={{appState, dispatch}}>
        <AppNotificationProviderWithProps {...createNotifiers({notifySuccess})}>
          <ProjectConfiguration />
        </AppNotificationProviderWithProps>
      </AppStateContext.Provider>
    );

    const textBox = await findByPlaceholderText('Project Title...');
    fireEvent.change(textBox, {target: {value: 'Some Title'}});
    const button = await findByText('Save & Next');
    fireEvent.click(button);
    await wait(() => expect(dispatch).toBeCalled());
    expect(dispatch.mock.calls[0][0]).toBeInstanceOf(CreateProjectAction);
    expect(notifySuccess).toBeCalled();
  });

  it('should notify on API error', async () => {
    const mockError = new Error('mock error');
    jest.spyOn(ProjectService.prototype, 'create').mockRejectedValueOnce(mockError);

    const appState: AppState = {
      runningProjects: [],
      activeProject: undefined,
      wizardState: {
        activeTab: WizardTabTypes.Project,
        done: {}
      }
    }

    const dispatch = jest.fn();
    const notifyError = jest.fn();
    const {findByPlaceholderText, findByText} = render(
      <AppStateContext.Provider value={{appState, dispatch}}>
        <AppNotificationProviderWithProps {...createNotifiers({notifyError})}>
          <ProjectConfiguration />
        </AppNotificationProviderWithProps>
      </AppStateContext.Provider>
    );

    const textBox = await findByPlaceholderText('Project Title...');
    fireEvent.change(textBox, {target: {value: 'Some Title'}});
    const button = await findByText('Save & Next');
    fireEvent.click(button);
    await wait(() => expect(notifyError).toBeCalledWith(expect.any(String), mockError));
  });

  it('should cancel', async () => {
    const appState: AppState = {
      runningProjects: [],
      activeProject: undefined,
      wizardState: {
        activeTab: WizardTabTypes.Project,
        done: {}
      }
    };

    const dispatch = jest.fn();
    const {findByText} = render(
      <AppStateContext.Provider value={{appState, dispatch}}>
        <ProjectConfiguration />
      </AppStateContext.Provider>
    );

    const cancel = await findByText('Cancel');
    fireEvent.click(cancel);
    await wait(() => expect(dispatch).toBeCalled());
    expect(dispatch.mock.calls[0][0]).toBeInstanceOf(ConfirmProjectSetupCancelAction);
  });

  describe('in edit mode', () => {
    it('should display project title', async () => {
      const appState: AppState = {
        runningProjects: [],
        activeProject: {id: 1, code: 'a', title: 'Yamamoto', running: false, autoStop: true},
        wizardState: {
          activeTab: WizardTabTypes.Project,
          done: {
            [WizardTabTypes.Project]: true
          }
        }
      };

      const dispatch = jest.fn();
      const {findByDisplayValue} = render(
        <AppStateContext.Provider value={{appState, dispatch}}>
          <ProjectConfiguration />
        </AppStateContext.Provider>
      );

      const editField = await findByDisplayValue('Yamamoto');
      expect(editField).toBeDefined();
    });

    it('should update project title', async () => {
      const updateSpy = jest.spyOn(ProjectService.prototype, 'update').mockResolvedValue(204);
      const appState: AppState = {
        runningProjects: [],
        activeProject: {id: 1, code: 'a', title: 'Yamamoto', running: false, autoStop: true},
        wizardState: {
          activeTab: WizardTabTypes.Project,
          done: {
            [WizardTabTypes.Project]: true
          }
        }
      };

      const dispatch = jest.fn();
      const notifySuccess = jest.fn();
      const {findByDisplayValue, findByText} = render(
        <AppStateContext.Provider value={{appState, dispatch}}>
          <AppNotificationProviderWithProps {...createNotifiers({notifySuccess})}>
            <ProjectConfiguration />
          </AppNotificationProviderWithProps>
        </AppStateContext.Provider>
      );

      const editField = await findByDisplayValue('Yamamoto');
      fireEvent.change(editField, {target: {value: 'Yamagoto'}});
      const submit = await findByText('Save & Next');
      fireEvent.click(submit);
      await wait(() => {
        expect(updateSpy).toBeCalledWith(appState.activeProject!.id, {title: 'Yamagoto'});
      });

      await wait(() => {
        expect(dispatch).toBeCalled();
        expect(dispatch.mock.calls[0][0]).toBeInstanceOf(UpdateProjectTitleAction);
        expect(notifySuccess).toBeCalled();
      });
    });

    it('should show validation message on title', async () => {
      const appState: AppState = {
        runningProjects: [],
        activeProject: {id: 1, code: 'a', title: 'Yamagoto', running: false, autoStop: true},
        wizardState: {
          activeTab: WizardTabTypes.Project,
          done: {
            [WizardTabTypes.Project]: true
          }
        }
      };

      const dispatch = jest.fn();
      const {findByDisplayValue, findByText, debug} = render(
        <AppStateContext.Provider value={{appState, dispatch}}>
          <ProjectConfiguration />
        </AppStateContext.Provider>
      );

      const editField = await findByDisplayValue('Yamagoto');
      fireEvent.change(editField, {target: {value: ''}});
      fireEvent.blur(editField);
      const errorMessage = await findByText(/blank/i);
      expect(errorMessage).toBeDefined();
    });
  });

  it('should go to next tab when Next is clicked', () => {
    const appState: AppState = {
      runningProjects: [],
      activeProject: {id: 1, code: 'a', title: 'Yamamoto', running: false},
      wizardState: {
        activeTab: WizardTabTypes.Project,
        done: {
          [WizardTabTypes.Project]: true
        }
      }
    };

    const dispatch = jest.fn();
    const component = mount(
      <AppStateContext.Provider value={{appState, dispatch}}>
        <ProjectConfiguration />
      </AppStateContext.Provider>
    );

    expect(component).toContainExactlyOneMatchingElement('NextLink .button');
    component.find('NextLink .button').simulate('click');
    expect(dispatch).toBeCalled();
    const action = dispatch.mock.calls[0][0] as Action;
    expect(action.payload).toEqual(WizardTabTypes.JMeter);
  });
});
