/* eslint-env jest */
import React from 'react'
import { mount, shallow } from 'enzyme'
import toJson from 'enzyme-to-json'
import renderer from 'react-test-renderer'
import { Login } from './Login'

describe('Login container', () => {
  it('it should render correctly', () => {
    const login = renderer.create(<Login
      location={{
        search: ''
      }}
      user={{
        account: null,
        data: {},
        hasMetamask: false,
        isLoading: false,
        error: false
      }}
    />)
    const tree = login.toJSON()
    expect(tree).toMatchSnapshot()
  })

  it('it should render any loader while not loaded', () => {
    const login = shallow(<Login
      location={{
        search: ''
      }}
      user={{
        account: null,
        data: {},
        hasMetamask: false,
        isLoading: true,
        error: false
      }}
    />)
    expect(toJson(login)).toMatchSnapshot()
  })

  it('it should render message about metamask was not detected', () => {
    const login = mount(<Login
      location={{
        search: ''
      }}
      user={{
        account: null,
        data: {},
        hasMetamask: false,
        isLoading: false,
        error: false
      }}
    />)
    expect(toJson(login)).toMatchSnapshot()
  })

  it('it should render message with metamask user account address', () => {
    const login = mount(<Login
      location={{
        search: ''
      }}
      user={{
        account: '0x23942983bc298374cjh',
        data: {},
        hasMetamask: true,
        isLoading: false,
        error: false
      }}
    />)
    expect(toJson(login)).toMatchSnapshot()
  })
})
