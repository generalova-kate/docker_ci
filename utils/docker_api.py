#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Copyright (C) 2019-2020 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
import logging
import os
import pathlib
import sys

import docker
import requests

from utils.exceptions import FailedStep

if sys.platform == 'win32':
    import pywintypes

log = logging.getLogger('project')


class DockerAPI:
    def __init__(self):
        # custom timeout to use Image.save() on large images - https://github.com/docker/docker-py/issues/2077
        self.client = docker.from_env(timeout=300)
        self.location = pathlib.Path(os.path.realpath(__file__)).parent.parent
        try:
            self.client.ping()
        except requests.exceptions.ConnectionError:
            raise FailedStep('Docker Engine is not running. Please start the docker daemon.')
        except pywintypes.error as ex:
            if ex.winerror == 2 and ex.funcname == 'WaitNamedPipe':
                raise FailedStep('Docker Engine is not running. Please start the docker daemon.')
            raise ex

    def __del__(self):
        self.client.close()

    def version(self):
        vers = self.client.version()
        for name in ['Version', 'ApiVersion', 'MinAPIVersion', 'Os', 'Arch', 'KernelVersion']:
            log.info(f'{name}: {vers[name]}')
