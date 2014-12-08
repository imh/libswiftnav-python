# Copyright (C) 2014 Swift Navigation Inc.
#
# This source is subject to the license found in the file 'LICENSE' which must
# be be distributed together with this source. All other rights reserved.
#
# THIS CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
# EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.

import numpy as np
cimport numpy as np
cimport amb_kf_c
from libc.string cimport memcpy, memcmp, memset
from almanac cimport *
from almanac_c cimport *
from gpstime cimport *
from gpstime_c cimport *
from single_diff_c cimport *
from dgnss_management_c cimport *

# def udu(M):
#   n = M.shape[0]
#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] M_ = \
#     np.array(M, dtype=np.double)
#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] U = \
#     np.empty((n,n), dtype=np.double)
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] D = \
#     np.empty(n, dtype=np.double)
#   amb_kf_c.udu(n, <double *> &M_[0,0], <double *> &U[0,0], <double *> &D[0])
#   return UDU_decomposition(U, D)

# def reconstruct_udu(ud):
#   n = ud.D.shape[0]

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] U = \
#     np.array(ud.U, dtype=np.double)
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] D = \
#     np.array(ud.D, dtype=np.double)

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] M = \
#     np.empty((n,n), dtype=np.double)

#   amb_kf_c.reconstruct_udu(n, <double *> &U[0,0], <double *> &D[0], <double *> &M[0,0])
#   return M

# def update_scalar_measurement(h, R, U, D):
#   state_dim = h.shape[0]

#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] h_ = \
#     np.array(h, dtype=np.double)
#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] U_ = \
#     np.array(U, dtype=np.double)
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] D_ = \
#     np.array(D, dtype=np.double)
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] k = \
#     np.empty(state_dim, dtype=np.double)

#   amb_kf_c.update_scalar_measurement(state_dim,
#                                        <double *> &h_[0],
#                                        <double> R,
#                                        <double *> &U_[0,0],
#                                        <double *> &D_[0],
#                                        <double *> &k[0])
#   return UDU_decomposition(U_, D_), k

# def filter_update(KalmanFilter kf, obs):
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] state_mean_ = \
#     np.empty(kf.state_dim, dtype=np.double)
#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] state_cov_U_ = \
#     np.empty((kf.state_dim, kf.state_dim), dtype=np.double)
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] state_cov_D_ = \
#     np.empty(kf.state_dim, dtype=np.double)
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] obs_ =  \
#     np.array(obs, dtype=np.double)

#   amb_kf_c.kalman_filter_update(&(kf.kf), <double *> &obs_[0])

#   memcpy(&state_mean_[0], kf.kf.state_mean, kf.state_dim * sizeof(double))
#   memcpy(&state_cov_U_[0,0], kf.kf.state_cov_U, kf.state_dim * kf.state_dim * sizeof(double))
#   memcpy(&state_cov_D_[0], kf.kf.state_cov_D, kf.state_dim * sizeof(double))

#   return state_mean_, UDU_decomposition(state_cov_U_, state_cov_D_)

# class UDU_decomposition:
#   def __init__(self, U, D):
#     self.U = U
#     self.D = D
#   def reconstruct(self):
#     return reconstruct_udu(self)

cdef class KalmanFilter:
  def __init__(self,
               amb_drift_var,
               np.ndarray[np.double_t, ndim=2, mode="c"] decor_mtx, 
               np.ndarray[np.double_t, ndim=2, mode="c"] decor_obs_mtx, 
               np.ndarray[np.double_t, ndim=1, mode="c"] decor_obs_cov,
               np.ndarray[np.double_t, ndim=2, mode="c"] null_basis_Q, 
               np.ndarray[np.double_t, ndim=1, mode="c"] state_mean,
               np.ndarray[np.double_t, ndim=2, mode="c"] state_cov_U,
               np.ndarray[np.double_t, ndim=1, mode="c"] state_cov_D,
               ):
    memset(&self.kf, 0, sizeof(amb_kf_c.nkf_t))
    self.state_dim = decor_mtx.shape[0]
    self.obs_dim = decor_mtx.shape[0] + max(0, decor_mtx.shape[0] - 3)
    self.amb_drift_var = amb_drift_var
    # self.num_sats = len(prns_with_ref_first)
    # self.prns_with_ref_first = prns_with_ref_first
    self.decor_mtx = decor_mtx
    self.decor_obs_mtx = decor_obs_mtx
    self.decor_obs_cov = decor_obs_cov
    self.null_basis_Q = null_basis_Q
    self.state_mean = state_mean
    self.state_cov_U = state_cov_U
    self.state_cov_D = state_cov_D

  def __init__(self):
    memset(&self.kf, 0, sizeof(amb_kf_c.nkf_t))

  def __repr__(self):
    return "<KalmanFilter with state_dim=" + str(self.state_dim) + \
           ", obs_dim=" + str(self.obs_dim) + ">"

  def testeq(KalmanFilter self, KalmanFilter other not None):
    print 0
    state_dim_eq = self.state_dim == other.state_dim
    print 1
    obs_dim_eq = self.obs_dim == other.obs_dim
    print 2
    amb_drift_vareq = self.amb_drift_var == other.amb_drift_var
    print 22
    decor_mtx_eq = bool(np.all(self.decor_mtx == other.decor_mtx))
    print 3
    decor_obs_mtx_eq = bool(np.all(self.decor_obs_mtx == other.decor_obs_mtx))
    print 4
    decor_obs_cov_eq = bool(np.all(self.decor_obs_cov == other.decor_obs_cov))
    print 5
    null_basis_Q_eq = bool(np.all(self.null_basis_Q == other.null_basis_Q))
    print 6
    state_mean_eq = bool(np.all(self.state_mean == other.state_mean))
    print 7
    state_cov_U_eq = bool(np.all(self.state_cov_U == other.state_cov_U))
    print 8
    state_cov_D_eq = bool(np.all(self.state_cov_D == other.state_cov_D))
    print 9
    eq_dict = {'state_dim'      : state_dim_eq,
               'obs_dim'        : obs_dim_eq,
               'amb_drift_var'  : amb_drift_vareq,
               'decor_mtx'      : decor_mtx_eq,
               'decor_obs_mtx'  : decor_obs_mtx_eq,
               'decor_obs_cov'  : decor_obs_cov_eq,
               'null_basis_Q'   : null_basis_Q_eq,
               'state_mean'     : state_mean_eq,
               'state_cov_U'    : state_cov_U_eq,
               'state_cov_D'    : state_cov_D_eq}
    print 10
    return all(eq_dict.values()), eq_dict



  def cmp(KalmanFilter self, KalmanFilter other not None):
    return memcmp(&self.kf, &other.kf, sizeof(amb_kf_c.nkf_t))

  def __richcmp__(KalmanFilter self, KalmanFilter other not None, int cmp_type):
    if not cmp_type == 2:
      raise NotImplementedError()
    return  0 == memcmp(&self.kf, &other.kf, sizeof(amb_kf_c.nkf_t))

  property state_dim:
    def __get__(self):
      # print -1
      return self.kf.state_dim
    def __set__(self, state_dim):
      self.kf.state_dim = state_dim

  property obs_dim:
    def __get__(self):
      # print -2
      return self.kf.obs_dim
    def __set__(self, obs_dim):
      self.kf.obs_dim = obs_dim

  property amb_drift_var:
    def __get__(self):
      return self.kf.amb_drift_var
    def __set__(self, amb_drift_var):
      self.kf.amb_drift_var = amb_drift_var

  # property num_sats:
  #   def __get__(self):
  #     return self.kf.num_sats
  #   def __set__(self, num_sats):
  #     self.kf.num_sats = num_sats

  # property prns_with_ref_first:
  #   def __get__(self):
  #     cdef np.ndarray[np.uint8_t, ndim=1, mode="c"] prns =\
  #       np.empty(self.num_sats, dtype=np.uint8)
  #     memcpy(&prns[0], self.kf.prns_with_ref_first, self.num_sats * sizeof(u8))
  #     return prns
  #   def __set__(self, np.ndarray[np.uint8_t, ndim=1, mode="c"] prns_with_ref_first):
  #     self.num_sats = len(prns_with_ref_first)
  #     memcpy(self.kf.prns_with_ref_first, &prns_with_ref_first[0], self.num_sats * sizeof(u8))

  property decor_mtx:
    def __get__(self):
      print 11
      cdef np.ndarray[np.double_t, ndim=2, mode="c"] decor_mtx = \
        np.empty((self.obs_dim/2, self.obs_dim/2), dtype=np.double)
      print 12
      memcpy(&decor_mtx[0,0], self.kf.decor_mtx, self.obs_dim * self.obs_dim * sizeof(double) / 4)
      print 13
      return decor_mtx
    def __set__(self, np.ndarray[np.double_t, ndim=2, mode="c"] decor_mtx):
      print 14
      memcpy(self.kf.decor_mtx, &decor_mtx[0,0], self.obs_dim * self.obs_dim * sizeof(double) / 4)
      print 15

  property decor_obs_mtx:
    def __get__(self):
      print 16
      cdef np.ndarray[np.double_t, ndim=2, mode="c"] decor_obs_mtx = \
        np.empty((self.obs_dim, self.state_dim), dtype=np.double)
      print 17
      memcpy(&decor_obs_mtx[0,0], self.kf.decor_obs_mtx, self.obs_dim * self.state_dim * sizeof(double))
      print 18
      return decor_obs_mtx
    def __set__(self, np.ndarray[np.double_t, ndim=2, mode="c"] decor_obs_mtx):
      memcpy(self.kf.decor_obs_mtx, &decor_obs_mtx[0,0], self.obs_dim * self.state_dim * sizeof(double))

  property decor_obs_cov:
    def __get__(self):
      print 19
      cdef np.ndarray[np.double_t, ndim=1, mode="c"] decor_obs_cov = \
        np.empty(self.obs_dim, dtype=np.double)
      print 20
      memcpy(&decor_obs_cov[0], self.kf.decor_obs_cov, self.obs_dim * sizeof(double))
      print 21
      return decor_obs_cov
    def __set__(self, np.ndarray[np.double_t, ndim=1, mode="c"] decor_obs_cov):
      memcpy(self.kf.decor_obs_cov, &decor_obs_cov[0], self.obs_dim * sizeof(double))

  property null_basis_Q:
    def __get__(self):
      print 22
      cdef np.ndarray[np.double_t, ndim=2, mode="c"] null_basis_Q = \
        np.empty((self.obs_dim - self.state_dim, self.state_dim), dtype=np.double)
      print 23
      memcpy(&null_basis_Q[0,0], self.kf.null_basis_Q, (self.obs_dim - self.state_dim) * self.state_dim * sizeof(double))
      print 24
      return null_basis_Q
    def __set__(self, np.ndarray[np.double_t, ndim=2, mode="c"] null_basis_Q):
      memcpy(self.kf.null_basis_Q, &null_basis_Q[0,0], (self.obs_dim - self.state_dim) * self.state_dim * sizeof(double))

  property state_mean:
    def __get__(self):
      # print 25
      cdef np.ndarray[np.double_t, ndim=1, mode="c"] state_mean = \
        np.empty(self.state_dim, dtype=np.double)
      # print 26
      memcpy(&state_mean[0], self.kf.state_mean, self.state_dim * sizeof(double))
      # print 27
      return state_mean
    def __set__(self, np.ndarray[np.double_t, ndim=1, mode="c"] state_mean):
      memcpy(self.kf.state_mean, &state_mean[0], self.state_dim * sizeof(double))

  property state_cov_U:
    def __get__(self):
      print 28
      cdef np.ndarray[np.double_t, ndim=2, mode="c"] state_cov_U = \
        np.empty((self.state_dim, self.state_dim), dtype=np.double)
      print 29
      memcpy(&state_cov_U[0,0], self.kf.state_cov_U, self.state_dim * self.state_dim * sizeof(double))
      print 30
      return state_cov_U
    def __set__(self, np.ndarray[np.double_t, ndim=2, mode="c"] state_cov_U):
      memcpy(self.kf.state_cov_U, &state_cov_U[0,0], self.state_dim * self.state_dim * sizeof(double))

  property state_cov_D:
    def __get__(self):
      print 31
      cdef np.ndarray[np.double_t, ndim=1, mode="c"] state_cov_D = \
        np.empty(self.state_dim, dtype=np.double)
      print 32
      memcpy(&state_cov_D[0], self.kf.state_cov_D, self.state_dim * sizeof(double))
      print 33
      return state_cov_D
    def __set__(self, np.ndarray[np.double_t, ndim=1, mode="c"] state_cov_D):
      memcpy(self.kf.state_cov_D, &state_cov_D[0], self.state_dim * sizeof(double))

  

# def get_transition_mtx(num_sats, dt):
#   state_dim = num_sats + 5
#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] transition_mtx = \
#         np.empty((state_dim, state_dim), dtype=np.double)
#   amb_kf_c.assign_transition_mtx(state_dim, dt, &transition_mtx[0,0])
#   return transition_mtx

# def get_d_mtx(num_sats):
#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] D = \
#         np.empty((num_sats - 1, num_sats), dtype=np.double)
#   amb_kf_c.assign_d_mtx(num_sats, &D[0,0])
#   return D

# def get_e_mtx_from_alms(alms, GpsTime timestamp, ref_ecef):
#   n = len(alms)
#   cdef almanac_t al[32]
#   cdef almanac_t a_
#   for i, a in enumerate(alms):
#     a_ = (<Almanac> a).almanac
#     memcpy(&al[i], &a_, sizeof(almanac_t))
  
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] ref_ecef_ = \
#     np.array(ref_ecef, dtype=np.double)

#   cdef gps_time_t timestamp_ = timestamp.gps_time

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] e_mtx = \
#         np.empty((len(alms), 3), dtype=np.double)

#   amb_kf_c.assign_e_mtx_from_alms(len(alms), &al[0], timestamp_, &ref_ecef_[0], &e_mtx[0,0])

#   return e_mtx

# def get_de_mtx_from_alms(alms, GpsTime timestamp, ref_ecef):
#   n = len(alms)
#   cdef almanac_t al[32]
#   cdef almanac_t a_
#   for i, a in enumerate(alms):
#     a_ = (<Almanac> a).almanac
#     memcpy(&al[i], &a_, sizeof(almanac_t))
  
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] ref_ecef_ = \
#     np.array(ref_ecef, dtype=np.double)

#   cdef gps_time_t timestamp_ = timestamp.gps_time

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] de_mtx = \
#         np.empty((len(alms) - 1, 3), dtype=np.double)

#   amb_kf_c.assign_de_mtx_from_alms(len(alms), &al[0], timestamp_, &ref_ecef_[0], &de_mtx[0,0])

#   return de_mtx

# def get_obs_mtx_from_alms_using_sdiffs(alms, GpsTime timestamp, ref_ecef):
#   n = len(alms)
#   state_dim = n + 5
#   obs_dim = 2 * (n-1)

#   cdef almanac_t al[32]
#   cdef almanac_t a_
#   for i, a in enumerate(alms):
#     a_ = (<Almanac> a).almanac
#     memcpy(&al[i], &a_, sizeof(almanac_t))
  
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] ref_ecef_ = \
#     np.array(ref_ecef, dtype=np.double)

#   cdef gps_time_t timestamp_ = timestamp.gps_time

#   cdef sdiff_t sdiffs[32]
#   almanacs_to_single_diffs(len(alms), &al[0], timestamp_, sdiffs)

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] obs_mtx = \
#         np.empty((obs_dim, state_dim), dtype=np.double)

#   amb_kf_c.assign_obs_mtx(len(alms), &sdiffs[0], &ref_ecef_[0], &obs_mtx[0,0])

#   return obs_mtx

# def get_obs_mtx_from_alms(alms, GpsTime timestamp, ref_ecef):
#   n = len(alms)
#   state_dim = n + 5
#   obs_dim = 2 * (n-1)

#   cdef almanac_t al[32]
#   cdef almanac_t a_
#   for i, a in enumerate(alms):
#     a_ = (<Almanac> a).almanac
#     memcpy(&al[i], &a_, sizeof(almanac_t))
  
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] ref_ecef_ = \
#     np.array(ref_ecef, dtype=np.double)

#   cdef gps_time_t timestamp_ = timestamp.gps_time

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] obs_mtx = \
#         np.empty((obs_dim, state_dim), dtype=np.double)

#   amb_kf_c.assign_obs_mtx_from_alms(len(alms), &al[0], timestamp_, &ref_ecef_[0], &obs_mtx[0,0])

#   return obs_mtx

# def get_decor_obs_cov(num_diffs, phase_var, code_var):
  
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] decor_obs_cov = \
#     np.empty(2 * num_diffs, dtype=np.double)

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] decor_mtx = \
#         np.empty((num_diffs, num_diffs), dtype=np.double)

#   amb_kf_c.assign_decor_obs_cov(num_diffs, phase_var, code_var, &decor_mtx[0,0], &decor_obs_cov[0])

#   return decor_mtx, decor_obs_cov

# def get_decor_obs_mtx_from_alms_using_sdiffs(alms, GpsTime timestamp, ref_ecef, decor_mtx):
#   n = len(alms)
#   state_dim = n + 5
#   obs_dim = 2 * (n-1)

#   cdef almanac_t al[32]
#   cdef almanac_t a_
#   for i, a in enumerate(alms):
#     a_ = (<Almanac> a).almanac
#     memcpy(&al[i], &a_, sizeof(almanac_t))
  
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] ref_ecef_ = \
#     np.array(ref_ecef, dtype=np.double)

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] decor_mtx_ = \
#     np.array(decor_mtx, dtype=np.double)

#   cdef gps_time_t timestamp_ = timestamp.gps_time

#   cdef sdiff_t sdiffs[32]
#   almanacs_to_single_diffs(len(alms), &al[0], timestamp_, sdiffs)

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] obs_mtx = \
#         np.empty((obs_dim, state_dim), dtype=np.double)

#   amb_kf_c.assign_decor_obs_mtx(len(alms), &sdiffs[0], &ref_ecef_[0],
#                                             &decor_mtx_[0,0], &obs_mtx[0,0])

#   return obs_mtx

# def get_decor_obs_mtx_from_alms(alms, GpsTime timestamp, ref_ecef, decor_mtx):
#   n = len(alms)
#   state_dim = n + 5
#   obs_dim = 2 * (n-1)

#   cdef almanac_t al[32]
#   cdef almanac_t a_
#   for i, a in enumerate(alms):
#     a_ = (<Almanac> a).almanac
#     memcpy(&al[i], &a_, sizeof(almanac_t))
  
#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] ref_ecef_ = \
#     np.array(ref_ecef, dtype=np.double)

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] decor_mtx_ = \
#     np.array(decor_mtx, dtype=np.double)

#   cdef gps_time_t timestamp_ = timestamp.gps_time

#   cdef np.ndarray[np.double_t, ndim=2, mode="c"] obs_mtx = \
#         np.empty((obs_dim, state_dim), dtype=np.double)

#   amb_kf_c.assign_decor_obs_mtx_from_alms(len(alms), &al[0], timestamp_, &ref_ecef_[0],
#                                             &decor_mtx_[0,0], &obs_mtx[0,0])

#   return obs_mtx


def get_kf_from_alms_using_sdiffs(phase_var, code_var,
                                  pos_trans_var, vel_trans_var, int_trans_var,
                                  amb_drift_var,
                                  pos_init_var, vel_init_var, int_init_var,
                                  alms, GpsTime timestamp,
                                  dd_measurements,
                                  ref_ecef, dt):
  n = len(alms)
  state_dim = n + 5
  obs_dim = 2 * (n-1)

  cdef almanac_t al[32]
  cdef almanac_t a_
  cdef np.ndarray[np.uint8_t, ndim=1, mode="c"] prns = \
        np.empty(n, dtype=np.uint8)
  for i, a in enumerate(alms):
    a_ = (<Almanac> a).almanac
    memcpy(&al[i], &a_, sizeof(almanac_t))
    prns[i] = (<Almanac> a).prn

  cdef np.ndarray[np.double_t, ndim=1, mode="c"] ref_ecef_ = \
    np.array(ref_ecef, dtype=np.double)

  cdef gps_time_t timestamp_ = timestamp.gps_time

  cdef sdiff_t sdiffs[32]
  almanacs_to_single_diffs(len(alms), &al[0], timestamp_, sdiffs)

  cdef np.ndarray[np.double_t, ndim=1, mode="c"] dd_measurements_ = \
    np.array(dd_measurements, dtype=np.double)

  cdef amb_kf_c.nkf_t kf
  amb_kf_c.set_nkf(&kf, amb_drift_var, phase_var, code_var, int_init_var,
                  n, &sdiffs[0], &dd_measurements_[0], &ref_ecef_[0])
  cdef KalmanFilter pykf = KalmanFilter()
  memcpy(&(pykf.kf), &kf, sizeof(amb_kf_c.nkf_t))

  return pykf
  
# def get_kf_from_alms(phase_var, code_var,
#                      pos_trans_var, vel_trans_var, int_trans_var,
#                      alms, GpsTime timestamp, ref_ecef, dt):
#   n = len(alms)
#   state_dim = n + 5
#   obs_dim = 2 * (n-1)

#   cdef almanac_t al[32]
#   cdef almanac_t a_
#   cdef np.ndarray[np.uint8_t, ndim=1, mode="c"] prns = \
#         np.empty(n, dtype=np.uint8)
#   for i, a in enumerate(alms):
#     a_ = (<Almanac> a).almanac
#     prn_ = (<Almanac> a).prn
#     memcpy(&al[i], &a_, sizeof(almanac_t))
#     prns[i] = (<Almanac> a).prn

#   cdef np.ndarray[np.double_t, ndim=1, mode="c"] ref_ecef_ = \
#     np.array(ref_ecef, dtype=np.double)

#   cdef gps_time_t timestamp_ = timestamp.gps_time

#   cdef amb_kf_c.nkf_t kf = amb_kf_c.get_kf_from_alms(phase_var, code_var,
#                                                         pos_trans_var, vel_trans_var, int_trans_var,
#                                                         n, &al[0], timestamp_, &ref_ecef_[0], dt)

#   cdef KalmanFilter pykf = KalmanFilter()
#   memcpy(&(pykf.kf), &kf, sizeof(amb_kf_c.nkf_t))

#   return pykf

  # cdef np.ndarray[np.double_t, ndim=2, mode="c"] transition_mtx = \
  #       np.empty((state_dim, state_dim), dtype=np.double)

  # cdef np.ndarray[np.double_t, ndim=2, mode="c"] transition_cov = \
  #       np.empty((state_dim, state_dim), dtype=np.double)

  # cdef np.ndarray[np.double_t, ndim=2, mode="c"] decor_mtx = \
  #       np.empty((n-1, n-1), dtype=np.double)

  # cdef np.ndarray[np.double_t, ndim=2, mode="c"] decor_obs_mtx = \
  #       np.empty((obs_dim, state_dim), dtype=np.double)

  # cdef np.ndarray[np.double_t, ndim=1, mode="c"] decor_obs_cov = \
  #       np.empty(obs_dim, dtype=np.double)

  # memcpy(&transition_mtx[0,0], kf.transition_mtx, state_dim * state_dim * sizeof(double))
  # memcpy(&transition_cov[0,0], kf.transition_cov, state_dim * state_dim * sizeof(double))
  # memcpy(&decor_mtx[0,0], kf.decor_mtx, (n-1) * (n-1) * sizeof(double))
  # memcpy(&decor_obs_mtx[0,0], kf.decor_obs_mtx, obs_dim * state_dim * sizeof(double))
  # memcpy(&decor_obs_cov[0], kf.decor_obs_cov, obs_dim * sizeof(double))

  # return KalmanFilter(prns,
  #                     transition_mtx,
  #                     transition_cov,
  #                     decor_mtx,
  #                     decor_obs_mtx,
  #                     decor_obs_cov)
